import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MODULE_FILE,
  OIDC_FILE,
  OIDC_VARS_FILE,
  RELEASE_FILE,
  RESOURCELESS_ACTIONS,
  compareSources,
  matchingBracket,
  parseOidcStack,
  parseReleaseWorkflow,
  parseStatements,
  parseWebStack,
  stringsFor,
  CLAIM_PREFIX,
  CLAIM_PREFIX_PATTERN,
} from './check_infra_iam.mjs';

// ─────────────────────────────── fixtures ───────────────────────────────
//
// Structurally faithful rather than minimal: the interpolated ARNs, the prose
// comment above an Action list, and the two-role shape are all things the real
// stack has, and each is something a naive read gets wrong.

/**
 * @param {string} env
 * @param {{ sub?: string, operator?: string, aud?: string, envToken?: string,
 *           name?: string, resources?: string[] }} [over]
 */
function role(env, over = {}) {
  const sub =
    over.sub ?? `repo:\${var.github_repo}:environment:${env === 'prod' ? 'production' : env}`;
  const operator = over.operator ?? 'StringEquals';
  const aud = over.aud ?? 'sts.amazonaws.com';
  const envToken = over.envToken ?? env;
  const name = over.name ?? `threkir-web-deploy-${env}`;
  const resources =
    over.resources ??
    [
      `arn:aws:s3:::threkir-web-${env}-site`,
      `arn:aws:s3:::threkir-web-${env}-site/*`,
    ];
  return (
    `resource "aws_iam_role" "deploy_${env}" {\n` +
    `  name = "${name}"\n` +
    `  assume_role_policy = jsonencode({\n` +
    `    Version = "2012-10-17"\n` +
    `    Statement = [{\n` +
    `      Effect    = "Allow"\n` +
    `      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }\n` +
    `      Action    = "sts:AssumeRoleWithWebIdentity"\n` +
    `      Condition = {\n` +
    `        ${operator} = {\n` +
    `          "token.actions.githubusercontent.com:aud" = "${aud}"\n` +
    `          "token.actions.githubusercontent.com:sub" = "${sub}"\n` +
    `        }\n` +
    `      }\n` +
    `    }]\n` +
    `  })\n` +
    `  tags = merge(local.oidc_tags, { Environment = "${envToken}" })\n` +
    `}\n\n` +
    `resource "aws_iam_role_policy" "deploy_${env}" {\n` +
    `  role = aws_iam_role.deploy_${env}.id\n` +
    `  name = "deploy-permissions"\n` +
    `  policy = jsonencode({\n` +
    `    Version = "2012-10-17"\n` +
    `    Statement = [\n` +
    `      {\n` +
    `        Sid      = "S3SyncSiteBucket"\n` +
    `        Effect   = "Allow"\n` +
    `        Action   = ["s3:PutObject", "s3:ListBucket"]\n` +
    `        Resource = [\n${resources.map((r) => `          "${r}",`).join('\n')}\n        ]\n` +
    `      },\n` +
    `      {\n` +
    `        Sid    = "CloudFrontInvalidate"\n` +
    `        Effect = "Allow"\n` +
    `        # ListDistributions: prose whose "quoted words" must not read as actions.\n` +
    `        Action = ["cloudfront:CreateInvalidation", "cloudfront:ListDistributions"]\n` +
    `        Resource = "*"\n` +
    `      },\n` +
    `      {\n` +
    `        Sid    = "LambdaUpdate"\n` +
    `        Effect = "Allow"\n` +
    `        Action = ["lambda:UpdateFunctionCode"]\n` +
    `        Resource = [\n` +
    `          "arn:aws:lambda:\${var.aws_region}:\${data.aws_caller_identity.current.account_id}:function:threkir-web-${env}-coach*",\n` +
    `        ]\n` +
    `      },\n` +
    `    ]\n` +
    `  })\n` +
    `}\n`
  );
}

const PROVIDER =
  'resource "aws_iam_openid_connect_provider" "github" {\n' +
  '  url            = "https://token.actions.githubusercontent.com"\n' +
  '  client_id_list = ["sts.amazonaws.com"]\n' +
  '}\n';

function oidcSource(prod = role('prod'), preview = role('preview')) {
  return `${PROVIDER}\n${prod}\n${preview}`;
}

const RELEASE =
  'jobs:\n' +
  '  release:\n' +
  '    environment:\n' +
  "      name: ${{ startsWith(github.ref, 'refs/tags/web@') && 'production' || 'preview' }}\n" +
  '    steps:\n' +
  '      - name: Determine env + version\n' +
  '        run: |\n' +
  '          if [[ "$GITHUB_REF" == refs/tags/web@* ]]; then\n' +
  '            echo "env=prod" >> "$GITHUB_OUTPUT"\n' +
  '          else\n' +
  '            echo "env=preview" >> "$GITHUB_OUTPUT"\n' +
  '          fi\n';

const MODULE =
  'locals {\n  resource_prefix = "threkir-web-${var.env}"\n}\n\n' +
  '# A comment whose stray brace { must not unbalance the scan.\n' +
  'resource "aws_lambda_function" "coach" {\n' +
  '  function_name = "${local.resource_prefix}-coach"\n' +
  '  environment {\n    variables = {\n      FOO = "bar"\n    }\n  }\n' +
  '}\n\n' +
  'resource "aws_lambda_alias" "live" {\n' +
  '  name             = "live"\n' +
  '  function_name    = aws_lambda_function.coach.function_name\n' +
  '  function_version = aws_lambda_function.coach.version\n' +
  '}\n\n' +
  'resource "aws_lambda_function_url" "coach" {\n' +
  '  function_name      = aws_lambda_function.coach.function_name\n' +
  '  qualifier          = aws_lambda_alias.live.name\n' +
  '  authorization_type = "AWS_IAM"\n' +
  '}\n\n' +
  'resource "aws_lambda_permission" "cf_url" {\n' +
  '  action        = "lambda:InvokeFunctionUrl"\n' +
  '  function_name = aws_lambda_function.coach.function_name\n' +
  '  qualifier     = aws_lambda_alias.live.name\n' +
  '  principal     = "cloudfront.amazonaws.com"\n' +
  '  source_arn    = aws_cloudfront_distribution.this.arn\n' +
  '}\n\n' +
  'resource "aws_lambda_permission" "cf_fn" {\n' +
  '  action        = "lambda:InvokeFunction"\n' +
  '  function_name = aws_lambda_function.coach.function_name\n' +
  '  qualifier     = aws_lambda_alias.live.name\n' +
  '  principal     = "cloudfront.amazonaws.com"\n' +
  '  source_arn    = aws_cloudfront_distribution.this.arn\n' +
  '}\n';

const VARS = 'variable "github_repo" {\n  type = string\n}\n';

/**
 * @param {{ oidc?: string, release?: string, module?: string, vars?: string }} [over]
 */
function run(over = {}) {
  return compareSources(
    parseOidcStack(over.oidc ?? oidcSource()),
    parseReleaseWorkflow(over.release ?? RELEASE),
    parseWebStack(over.module ?? MODULE),
    over.vars ?? VARS,
  );
}

/** @param {string[]} errors @param {RegExp} re */
function has(errors, re) {
  return errors.some((e) => re.test(e));
}

// ─────────────────────────── the happy fixture ───────────────────────────

test('the faithful fixture passes, so every failure below is the mutation', () => {
  const { errors, ok } = run();
  assert.deepEqual(errors, []);
  assert.ok(ok.length > 5);
});

// ─────────────────────────── value readers ───────────────────────────────

test('stringsFor reads both the scalar and the list form', () => {
  assert.deepEqual(stringsFor('Resource = "*"', 'Resource'), ['*']);
  assert.deepEqual(stringsFor('Action = ["a:B", "c:D"]', 'Action'), ['a:B', 'c:D']);
  assert.equal(stringsFor('Effect = "Allow"', 'Resource'), null);
});

test('stringsFor does not answer with a key that merely ends the same way', () => {
  // `NotAction` is a real IAM key and the opposite of `Action`; matching it
  // would read a deny-list as the grant.
  assert.equal(stringsFor('NotAction = ["s3:*"]', 'Action'), null);
});

test('matchingBracket ignores a bracket inside a string', () => {
  const src = '["a]b", "c"]';
  assert.equal(matchingBracket(src, 0), src.length - 1);
});

test('parseStatements keeps each statement separate', () => {
  const parsed = parseStatements(
    'Statement = [\n  { Sid = "A", Action = ["x:Y"], Resource = "*" },\n' +
      '  { Sid = "B", Action = ["z:W"], Resource = ["arn:aws:s3:::b"] },\n]',
  );
  assert.deepEqual(
    parsed.map((s) => s.sid),
    ['A', 'B'],
  );
  assert.deepEqual(parsed[1].resources, ['arn:aws:s3:::b']);
});

// ───────────────────────── 1. trust-policy shape ─────────────────────────

test('StringLike instead of StringEquals fails', () => {
  const { errors } = run({
    oidc: oidcSource(role('prod', { operator: 'StringLike' }), role('preview')),
  });
  assert.ok(has(errors, /must be exactly \["StringEquals"\]/), errors.join('\n'));
});

test('a wildcarded sub fails', () => {
  const { errors } = run({
    oidc: oidcSource(
      role('prod', { sub: 'repo:${var.github_repo}:*' }),
      role('preview'),
    ),
  });
  assert.ok(has(errors, /contains a wildcard/), errors.join('\n'));
});

test('a ref-shaped sub fails — it is assumable from any matching branch', () => {
  const { errors } = run({
    oidc: oidcSource(
      role('prod', { sub: 'repo:${var.github_repo}:ref:refs/tags/web@1.0.0' }),
      role('preview'),
    ),
  });
  assert.ok(has(errors, /not `repo:<owner\/repo>:environment:<name>`/), errors.join('\n'));
});

test('a pull_request-shaped sub fails', () => {
  const { errors } = run({
    oidc: oidcSource(
      role('prod', { sub: 'repo:${var.github_repo}:pull_request' }),
      role('preview'),
    ),
  });
  assert.ok(has(errors, /not `repo:<owner\/repo>:environment:<name>`/), errors.join('\n'));
});

test('an unpinned audience fails', () => {
  const { errors } = run({
    oidc: oidcSource(role('prod', { aud: 'anything' }), role('preview')),
  });
  assert.ok(has(errors, /does not pin .*:aud/), errors.join('\n'));
});

test('an extra provider audience fails', () => {
  const { errors } = run({
    oidc: oidcSource().replace(
      'client_id_list = ["sts.amazonaws.com"]',
      'client_id_list = ["sts.amazonaws.com", "any"]',
    ),
  });
  assert.ok(has(errors, /client_id_list/), errors.join('\n'));
});

test('a role name that disagrees with its Environment tag fails', () => {
  const { errors } = run({
    oidc: oidcSource(role('prod', { name: 'threkir-web-deploy' }), role('preview')),
  });
  assert.ok(has(errors, /does not end in its Environment tag/), errors.join('\n'));
});

test('a github_repo variable with a default fails', () => {
  const { errors } = run({
    vars: 'variable "github_repo" {\n  type = string\n  default = "someone/else"\n}\n',
  });
  assert.ok(has(errors, /gives `github_repo` a default/), errors.join('\n'));
});

// ─────────────────── 2. environment lockstep ────────────────────

test('renaming the GitHub environment on one side alone fails', () => {
  // Exactly the web@1.0.3 failure: the workflow moves, the trust policy does not.
  const { errors } = run({
    release: RELEASE.replace("'production'", "'prod-gated'"),
  });
  assert.ok(has(errors, /can declare GitHub environment\(s\) \["prod-gated"\]/), errors.join('\n'));
  assert.ok(has(errors, /trust GitHub environment\(s\) \["production"\]/), errors.join('\n'));
});

test('crossing the two environments fails', () => {
  const { errors } = run({
    oidc: oidcSource(
      role('prod', { sub: 'repo:${var.github_repo}:environment:preview' }),
      role('preview', { sub: 'repo:${var.github_repo}:environment:production' }),
    ),
  });
  assert.ok(
    has(errors, /would be assuming the other environment's role/),
    errors.join('\n'),
  );
});

test('a workflow whose branches can no longer be read fails loudly', () => {
  const { errors } = run({ release: 'jobs:\n  release:\n    steps: []\n' });
  assert.ok(has(errors, /could not read both branches/), errors.join('\n'));
});

// ───────────────────── 3. wildcard grants ─────────────────────

test('a service-wide action fails', () => {
  const { errors } = run({
    oidc: oidcSource().replace('"s3:PutObject", "s3:ListBucket"', '"s3:*"'),
  });
  assert.ok(has(errors, /A service-wide action grant/), errors.join('\n'));
});

test('a new action on Resource "*" fails until it is exempted with a reason', () => {
  const { errors } = run({
    oidc: oidcSource().replaceAll(
      '"cloudfront:CreateInvalidation", "cloudfront:ListDistributions"',
      '"cloudfront:CreateInvalidation", "cloudfront:ListDistributions", "iam:PassRole"',
    ),
  });
  assert.ok(has(errors, /grants "iam:PassRole" on Resource "\*"/), errors.join('\n'));
});

test('an exemption nothing uses fails', () => {
  const { errors } = run({
    oidc: oidcSource().replaceAll('"cloudfront:ListDistributions"', '"cloudfront:CreateInvalidation"'),
  });
  assert.ok(has(errors, /RESOURCELESS_ACTIONS exempts "cloudfront:ListDistributions"/), errors.join('\n'));
});

test('the exemption list carries a reason for every entry', () => {
  for (const [action, reason] of RESOURCELESS_ACTIONS) {
    assert.ok(reason.length > 20, `${action} needs a real reason, not a placeholder`);
  }
});

// ─────────────── 4. one environment per role ────────────────

test('a preview role reaching a prod bucket fails', () => {
  const { errors } = run({
    oidc: oidcSource(
      role('prod'),
      role('preview', {
        resources: ['arn:aws:s3:::threkir-web-prod-site', 'arn:aws:s3:::threkir-web-prod-site/*'],
      }),
    ),
  });
  assert.ok(has(errors, /belongs to prod/), errors.join('\n'));
});

test('a resource wildcarding its account field fails', () => {
  const { errors } = run({
    oidc: oidcSource().replace(
      '${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-coach*',
      '*:function:threkir-web-prod-coach*',
    ),
  });
  assert.ok(has(errors, /wildcards its region or account field/), errors.join('\n'));
});

// ───────────────── 5. Lambda coverage ─────────────────

test('a Lambda the module declares but the deploy policy omits fails', () => {
  const extended =
    MODULE +
    '\nresource "aws_lambda_function" "share_run" {\n' +
    '  function_name = "${local.resource_prefix}-share-run"\n}\n';
  const { errors } = run({ module: extended });
  assert.ok(has(errors, /declares Lambda\(s\) \["share-run"\]/), errors.join('\n'));
  assert.ok(has(errors, /AccessDenied/), errors.join('\n'));
});

test('a deploy grant naming a function the module does not declare fails', () => {
  const { errors } = run({
    oidc: oidcSource().replace(
      'function:threkir-web-prod-coach*',
      'function:threkir-web-prod-ghost*',
    ),
  });
  assert.ok(has(errors, /grants Lambda\(s\) \["ghost"\]/), errors.join('\n'));
});

// ───────────── 6. Function URL reachability ─────────────

test('a Function URL left unauthenticated fails', () => {
  const { errors } = run({
    module: MODULE.replace('authorization_type = "AWS_IAM"', 'authorization_type = "NONE"'),
  });
  assert.ok(has(errors, /world-invocable/), errors.join('\n'));
});

test('dropping the plain lambda:InvokeFunction grant fails — issue #590', () => {
  const { errors } = run({
    module: MODULE.replace(/resource "aws_lambda_permission" "cf_fn" \{[\s\S]*?\n\}\n/, ''),
  });
  assert.ok(has(errors, /needs BOTH grants/), errors.join('\n'));
});

test('a grant open to any distribution fails', () => {
  const { errors } = run({
    module: MODULE.replaceAll(
      'source_arn    = aws_cloudfront_distribution.this.arn',
      'source_arn    = "*"',
    ),
  });
  assert.ok(has(errors, /any CloudFront distribution in any account/), errors.join('\n'));
});

// ───────────────────── the committed sources ─────────────────────

test('the committed infra/ tree satisfies every rule above', () => {
  const { errors, ok } = compareSources(
    parseOidcStack(readFileSync(OIDC_FILE, 'utf-8')),
    parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8')),
    parseWebStack(readFileSync(MODULE_FILE, 'utf-8')),
    readFileSync(OIDC_VARS_FILE, 'utf-8'),
  );
  assert.deepEqual(errors, []);
  assert.ok(ok.length >= 10, 'a passing run that checked almost nothing is not a pass');
});

test('the parsers actually reach the committed sources', () => {
  const oidc = parseOidcStack(readFileSync(OIDC_FILE, 'utf-8'));
  assert.equal(oidc.roles.length, 2);
  assert.equal(oidc.policies.length, 2);
  const web = parseWebStack(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(web.functions.size >= 8, 'the module declares at least the eight web Lambdas');
  assert.equal(web.urls.size, web.functions.size);
  const release = parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8'));
  assert.equal(release.environment.whenTrue, 'production');
  assert.equal(release.resourceEnv.whenTrue, 'prod');
});

// The regex-safe spelling is a second copy of the claim prefix. Nothing but
// this pins them together, and a prefix that drifts from its pattern reads
// every trust policy as having no claims at all — the guard would pass an
// empty condition rather than fail it.
test('the claim prefix and its regex-safe spelling describe the same host', () => {
  assert.match(CLAIM_PREFIX, new RegExp(`^${CLAIM_PREFIX_PATTERN}$`));
  assert.doesNotMatch('tokenXactionsXgithubusercontentXcom', new RegExp(`^${CLAIM_PREFIX_PATTERN}$`));
});

// ───────────── 7. alias lockstep + what the parser skipped ─────────────
//
// The Function URL is created ON the alias, so CloudFront invokes the alias
// ARN. Lambda attaches a resource-policy statement per qualifier: a grant
// written without one covers the unqualified function and not the ARN the URL
// actually invokes. That is issue #590's failure exactly, one field over — the
// URL 403s before invocation and the distribution rewrites the 403 into the
// SPA shell at 200, so the surface renders while the Lambda never runs.

test('a grant that drops the alias qualifier fails', () => {
  const { errors } = run({
    module: MODULE.replace(
      '  action        = "lambda:InvokeFunction"\n' +
        '  function_name = aws_lambda_function.coach.function_name\n' +
        '  qualifier     = aws_lambda_alias.live.name\n',
      '  action        = "lambda:InvokeFunction"\n' +
        '  function_name = aws_lambda_function.coach.function_name\n',
    ),
  });
  assert.ok(has(errors, /grant by null/), errors.join('\n'));
  assert.ok(has(errors, /issue #590/), errors.join('\n'));
});

test('a Function URL qualified by another function\'s alias fails', () => {
  const module =
    MODULE +
    '\nresource "aws_lambda_function" "share_run" {\n' +
    '  function_name = "${local.resource_prefix}-share-run"\n}\n' +
    '\nresource "aws_lambda_alias" "share_run_live" {\n' +
    '  name          = "live"\n' +
    '  function_name = aws_lambda_function.share_run.function_name\n}\n';
  const { errors } = run({
    module: module.replace(
      'resource "aws_lambda_function_url" "coach" {\n' +
        '  function_name      = aws_lambda_function.coach.function_name\n' +
        '  qualifier          = aws_lambda_alias.live.name\n',
      'resource "aws_lambda_function_url" "coach" {\n' +
        '  function_name      = aws_lambda_function.coach.function_name\n' +
        '  qualifier          = aws_lambda_alias.share_run_live.name\n',
    ),
  });
  assert.ok(has(errors, /an alias of share_run/), errors.join('\n'));
});

test('a Function URL qualified by an alias the module does not declare fails', () => {
  const { errors } = run({
    module: MODULE.replace('aws_lambda_alias.live.name\n' + '  authorization_type', 'aws_lambda_alias.ghost.name\n' + '  authorization_type'),
  });
  assert.ok(has(errors, /does not name an aws_lambda_alias this module declares/), errors.join('\n'));
});

// A block written so the function-name regex misses it is skipped, and the
// loop then has one fewer thing to iterate — which looks exactly like a stack
// with one fewer Lambda. Only the declared-vs-read count can tell them apart.
test('a Function URL the parser could not attribute fails rather than vanishing', () => {
  const { errors } = run({
    module:
      MODULE +
      '\nresource "aws_lambda_function_url" "ghost" {\n' +
      '  function_name      = local.some_other_reference\n' +
      '  authorization_type = "NONE"\n}\n',
  });
  assert.ok(has(errors, /2 aws_lambda_function_url block\(s\) in the module, 1 read/), errors.join('\n'));
});

test('an aws_lambda_permission naming no function fails rather than vanishing', () => {
  const { errors } = run({
    module:
      MODULE +
      '\nresource "aws_lambda_permission" "ghost" {\n' +
      '  action        = "lambda:InvokeFunction"\n' +
      '  function_name = local.some_other_reference\n' +
      '  principal     = "*"\n}\n',
  });
  assert.ok(has(errors, /name no aws_lambda_function/), errors.join('\n'));
});

test('parseWebStack reads the committed module\'s aliases and qualifiers', () => {
  const web = parseWebStack(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(web.aliases.size >= 8, `read only ${web.aliases.size} aliases`);
  assert.equal(web.declared.urls, web.urls.size);
  assert.equal(web.permissions.filter((p) => p.fn === null).length, 0);
  for (const [fn, url] of web.urls) {
    assert.ok(url.qualifier, `${fn}: no qualifier read off the Function URL`);
  }
});
