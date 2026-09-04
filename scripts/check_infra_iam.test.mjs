import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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
  parseSecretMerges,
  parseWebStack,
  stringsFor,
  CLAIM_PREFIX,
  CLAIM_PREFIX_PATTERN,
  ACTION_DIR,
  CREDENTIALS_ACTION,
  ENV_FILES,
  credentialedActions,
  WORKFLOW_DIR,
  checkDecryptGrant,
  parseEnvWire,
  parseKmsDecryptGrant,
  parseWorkflowJobs,
  UNEXERCISED_LAMBDA_ACTIONS,
  checkLambdaActionScope,
  iamActionForCliVerb,
  scanWorkflowLambdaActions,
  jobRegions,
  parseBranchOutputs,
  envsForCondition,
  readWorkflowFiles,
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
  'locals {\n  resource_prefix = "threkir-web-${var.env}"\n' +
  '  coach_secret_keys = ["ANTHROPIC_API_KEY"]\n' +
  '  lambda_env = merge(\n' +
  '    local.base_lambda_env,\n' +
  '    local.has_secrets ? { for k, v in data.sops_file.secrets[0].data : k => v if contains(local.coach_secret_keys, k) } : {},\n' +
  '  )\n}\n\n' +
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

// ───────────── 8. what reaches a Lambda's environment ─────────────
//
// The coach env used to be `local.has_secrets ? data.sops_file.secrets[0].data
// : {}` — the whole decrypted file. Every key it grows for any other consumer
// lands in that function's environment whether the handler reads it or not,
// and the Terraform reads as the same tidy merge() line either way.

test('a Lambda env that merges the whole sops map fails', () => {
  const { errors } = run({
    module: MODULE.replace(
      '{ for k, v in data.sops_file.secrets[0].data : k => v if contains(local.coach_secret_keys, k) }',
      'data.sops_file.secrets[0].data',
    ),
  });
  assert.ok(has(errors, /local\.lambda_env merges the decrypted sops map whole/), errors.join('\n'));
});

test('a Lambda env with no sops reference at all fails rather than passing', () => {
  const { errors } = run({
    module: MODULE.replace(
      'local.has_secrets ? { for k, v in data.sops_file.secrets[0].data : k => v if contains(local.coach_secret_keys, k) } : {},\n',
      '',
    ),
  });
  assert.ok(has(errors, /no `\*_lambda_env` local was read/), errors.join('\n'));
});

test('parseSecretMerges tells a filtered reference from a bare one', () => {
  const filtered = parseSecretMerges(
    'locals {\n  a_lambda_env = merge(\n' +
      '    { X = 1 },\n' +
      '    { for k, v in data.sops_file.secrets[0].data : k => v if k == "A" || k == "B" },\n  )\n}\n',
  );
  assert.deepEqual(filtered, [{ local: 'a_lambda_env', filter: 'k == "A" || k == "B"' }]);

  const bare = parseSecretMerges(
    'locals {\n  b_lambda_env = merge(\n    { X = 1 },\n    data.sops_file.secrets[0].data,\n  )\n}\n',
  );
  assert.deepEqual(bare, [{ local: 'b_lambda_env', filter: null }]);
});

// A comprehension with no `if` admits the whole map through a shape that looks
// filtered, which is the one way past this reader worth spelling out.
test('parseSecretMerges refuses a comprehension carrying no predicate', () => {
  const out = parseSecretMerges(
    'locals {\n  c_lambda_env = merge(\n' +
      '    { for k, v in data.sops_file.secrets[0].data : k => v },\n  )\n}\n',
  );
  assert.deepEqual(out, [{ local: 'c_lambda_env', filter: null }]);
});

test('the committed module takes only named keys into every Lambda env', () => {
  const web = parseWebStack(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(web.secretMerges.length >= 2, JSON.stringify(web.secretMerges));
  for (const merge of web.secretMerges) {
    assert.ok(merge.filter, `local.${merge.local} takes the sops file whole`);
  }
});

// ───────────────────── claim 9: the decrypt grant ─────────────────────

/// A key-policy document shaped like the real one: the root ADMIN statement
/// (no data-plane action), the root SOPS statement (which DOES carry
/// kms:Decrypt and must not be mistaken for the pipeline grant), and the
/// Lambda/deploy statement the claim is about.
/** @param {{ principal?: string, decryptStatement?: boolean }} [over] */
function keyPolicy(over = {}) {
  const principal = over.principal ?? '        var.kms_decrypt_principal_arn,\n';
  const decrypt =
    over.decryptStatement === false
      ? ''
      : '  statement {\n' +
        '    sid    = "AllowLambdaAndDeployRolesToDecrypt"\n' +
        '    principals {\n' +
        '      type = "AWS"\n' +
        '      identifiers = compact([\n' +
        '        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.resource_prefix}-coach-lambda",\n' +
        principal +
        '      ])\n' +
        '    }\n' +
        '    actions = [\n      "kms:Decrypt",\n      "kms:DescribeKey",\n    ]\n' +
        '    resources = ["*"]\n' +
        '  }\n';
  return (
    'data "aws_iam_policy_document" "kms_secrets" {\n' +
    '  statement {\n' +
    '    sid    = "AllowKeyAdministrationByAccountRoot"\n' +
    '    principals {\n      type        = "AWS"\n' +
    '      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]\n    }\n' +
    '    actions = ["kms:Describe*"]\n  }\n' +
    '  statement {\n' +
    '    sid    = "AllowOperatorSopsUseViaIamPolicies"\n' +
    '    principals {\n      type        = "AWS"\n' +
    '      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]\n    }\n' +
    '    actions = ["kms:Encrypt", "kms:Decrypt"]\n  }\n' +
    decrypt +
    '}\n'
  );
}

/** @param {{ kms?: boolean }} [over] */
function lambdaFn(over = {}) {
  return (
    'resource "aws_lambda_function" "coach" {\n' +
    '  function_name = "${local.resource_prefix}-coach"\n' +
    (over.kms ? '  kms_key_arn   = aws_kms_key.secrets.arn\n' : '') +
    '}\n'
  );
}

/** @param {string | null} wire */
function envRoot(wire) {
  return (
    'module "web" {\n  source = "../../modules/web-stack"\n' +
    (wire === null ? '' : `  kms_decrypt_principal_arn = ${wire}\n`) +
    '  env = "prod"\n}\n'
  );
}

/** @param {{ credentialed?: boolean, terraform?: string | null }} [over] */
function workflow(over = {}) {
  const cred = over.credentialed ?? false;
  const tf = over.terraform === undefined ? null : over.terraform;
  return (
    'jobs:\n  deploy:\n    runs-on: ubuntu-latest\n    steps:\n' +
    '      - uses: actions/checkout@v7\n' +
    (cred ? `      - uses: ${CREDENTIALS_ACTION}\n` : '') +
    (tf === null ? '' : `      - name: infra\n        run: |\n          ${tf}\n`)
  );
}

/**
 * @param {{ policy?: string, fn?: string, envs?: (string | null)[], wf?: string }} [over]
 */
function grantRun(over = {}) {
  const module = (over.policy ?? keyPolicy()) + (over.fn ?? lambdaFn());
  const envs = (over.envs ?? [null, null]).map((wire, i) => ({
    path: `envs/${i}/main.tf`,
    ...parseEnvWire(envRoot(wire)),
  }));
  const jobs = parseWorkflowJobs([
    { name: 'w.yml', text: over.wf ?? workflow({ credentialed: true }) },
  ]);
  return checkDecryptGrant(parseKmsDecryptGrant(module), envs, jobs);
}

test('an unwired decrypt principal passes while neither premise is broken', () => {
  const { errors, ok } = grantRun();
  assert.deepEqual(errors, []);
  assert.ok(ok.some((l) => /no CI decrypt principal/.test(l)), ok.join('\n'));
});

test('wiring a deploy role in while nothing exercises it is standing privilege', () => {
  const { errors } = grantRun({
    envs: ['data.terraform_remote_state.github_oidc.outputs.deploy_role_arn_prod', null],
  });
  assert.ok(has(errors, /standing privilege/), errors.join('\n'));
  assert.equal(errors.length, 1);
});

// The module default is `""`, so an explicit empty string is the same posture
// as omitting the argument and must not read as a grant.
test('an explicitly empty wire is not read as a grant', () => {
  const { errors } = grantRun({ envs: ['""', '""'] });
  assert.deepEqual(errors, []);
});

test('a Lambda holding its env under the CMK demands the wire back', () => {
  const { errors } = grantRun({ fn: lambdaFn({ kms: true }) });
  assert.equal(errors.length, 2, errors.join('\n'));
  assert.ok(has(errors, /set\(s\) kms_key_arn/), errors.join('\n'));
});

test('a credentialed job running terraform demands the wire back', () => {
  const { errors } = grantRun({
    wf: workflow({ credentialed: true, terraform: 'terraform apply -auto-approve' }),
  });
  assert.ok(has(errors, /assume\(s\) an AWS role AND run\(s\) terraform/), errors.join('\n'));
});

// terraform.yml is exactly this shape — it runs fmt/init/validate on every PR
// with no credentials at all, so its terraform can never reach KMS.
test('an UNcredentialed job running terraform demands nothing', () => {
  const { errors } = grantRun({
    wf: workflow({ credentialed: false, terraform: 'terraform validate -no-color' }),
  });
  assert.deepEqual(errors, []);
});

// The four `terraform apply` mentions in ci.yml's and terraform.yml's own
// comments are prose. A reader that counted them would demand a grant for a
// pipeline step that does not exist.
test('terraform named only in a comment is not a run', () => {
  const jobs = parseWorkflowJobs([
    {
      name: 'ci.yml',
      text:
        'jobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n' +
        `      - uses: ${CREDENTIALS_ACTION}\n` +
        '      # decisions.md § 433 — an env-only `terraform apply` publishes a fresh\n' +
        '      - name: build\n        run: |\n' +
        '          # would be nice to discover this before `terraform apply`\n' +
        '          echo hi\n',
    },
  ]);
  assert.deepEqual(
    jobs.map((j) => [j.job, j.credentialed, j.terraform]),
    [['build', true, false]],
  );
});

test('a chained terraform after && is still a run', () => {
  const jobs = parseWorkflowJobs([
    {
      name: 'w.yml',
      text:
        'jobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n' +
        '      - name: x\n        run: cd infra/envs/prod && terraform apply -auto-approve\n',
    },
  ]);
  assert.equal(jobs[0].terraform, true);
});

test('deleting the decrypt statement fails rather than passing vacuously', () => {
  const { errors } = grantRun({ policy: keyPolicy({ decryptStatement: false }) });
  assert.ok(has(errors, /no kms:Decrypt statement with an AWS principal/), errors.join('\n'));
});

test('dropping the restore knob from the statement fails', () => {
  const { errors } = grantRun({ policy: keyPolicy({ principal: '' }) });
  assert.ok(has(errors, /no longer takes `var\.kms_decrypt_principal_arn`/), errors.join('\n'));
});

test('an unreadable env root is reported, not skipped', () => {
  const { errors } = checkDecryptGrant(
    parseKmsDecryptGrant(keyPolicy() + lambdaFn()),
    [{ path: 'envs/prod/main.tf', ...parseEnvWire('# the module call moved\n') }],
    parseWorkflowJobs([{ name: 'w.yml', text: workflow({ credentialed: true }) }]),
  );
  assert.ok(has(errors, /holds no `module "web"` block/), errors.join('\n'));
});

test('an empty workflow scan is reported, not treated as "nothing applies"', () => {
  const { errors } = grantRun({ wf: 'name: nothing\n' });
  assert.ok(has(errors, /rests on an empty scan/), errors.join('\n'));
});

// The committed sources, not a fixture: this is the claim the repo makes.
test('the committed infra leaves no CI decrypt principal on either secrets CMK', () => {
  const grant = parseKmsDecryptGrant(readFileSync(MODULE_FILE, 'utf-8'));
  assert.equal(grant.found, true);
  assert.deepEqual(grant.cmkEnvFunctions, []);
  assert.ok(grant.identifiers.includes('var.kms_decrypt_principal_arn'));
  for (const path of ENV_FILES) {
    const { hasModuleCall, wire } = parseEnvWire(readFileSync(path, 'utf-8'));
    assert.ok(hasModuleCall, path);
    assert.ok(wire === null || wire === '""', `${path} wires ${wire}`);
  }
  const jobs = parseWorkflowJobs(readWorkflowFiles(WORKFLOW_DIR));
  assert.ok(jobs.length > 20, `only ${jobs.length} workflow jobs read`);
  assert.deepEqual(
    jobs.filter((j) => j.credentialed && j.terraform).map((j) => `${j.file}:${j.job}`),
    [],
  );
  // Both halves must be non-vacuous: something IS credentialed and something
  // DOES run terraform, or the scan proves nothing about the combination.
  assert.ok(jobs.some((j) => j.credentialed));
  assert.ok(jobs.some((j) => j.terraform));
});

// The workflow scan reads .github/workflows/*.yml only, so the claim rests on
// no composite action holding AWS credentials. That premise is asserted rather
// than assumed, and asserting it is what turns a blind spot into a failure.
test('a composite action assuming an AWS role fails the claim', () => {
  const { errors } = grantRun();
  assert.deepEqual(errors, []);
  const withAction = checkDecryptGrant(
    parseKmsDecryptGrant(keyPolicy() + lambdaFn()),
    [{ path: 'envs/prod/main.tf', ...parseEnvWire(envRoot(null)) }],
    parseWorkflowJobs([{ name: 'w.yml', text: workflow({ credentialed: true }) }]),
    ['deploy-infra'],
  );
  assert.ok(has(withAction.errors, /composite action\(s\) deploy-infra/), withAction.errors.join('\n'));
});

test('neither committed composite action assumes an AWS role', () => {
  assert.deepEqual(credentialedActions(ACTION_DIR), []);
});

test('credentialedActions on a missing directory is empty, not a throw', () => {
  assert.deepEqual(credentialedActions(join(ACTION_DIR, 'does-not-exist')), []);
});

// ───────────── claim 10: lambda verb scope ─────────────

/// A workflow that deploys BOTH environments from one job, as release-web.yml
/// does. `prodOnly` is the verb only the production leg runs, gated on the
/// same `is_prod` output the real workflow already gates two steps on.
/** @param {{ prodOnly?: string }} [over] */
const twoEnvWorkflow = (over = {}) =>
  [
    'jobs:',
    '  release:',
    '    environment:',
    "      name: ${{ startsWith(github.ref, 'refs/tags/web@') && 'production' || 'preview' }}",
    '    steps:',
    '      - name: Determine env',
    '        id: env',
    '        run: |',
    '          if [[ "$GITHUB_REF" == refs/tags/web@* ]]; then',
    '            echo "env=prod" >> "$GITHUB_OUTPUT"',
    '            echo "is_prod=true" >> "$GITHUB_OUTPUT"',
    '          else',
    '            echo "env=preview" >> "$GITHUB_OUTPUT"',
    '            echo "is_prod=false" >> "$GITHUB_OUTPUT"',
    '          fi',
    '      - name: Pick deploy role ARN',
    '        env:',
    '          ARN_PROD: ${{ secrets.AWS_DEPLOY_ROLE_ARN_PROD }}',
    '          ARN_PREVIEW: ${{ secrets.AWS_DEPLOY_ROLE_ARN_PREVIEW }}',
    '        run: echo picked',
    `      - uses: ${CREDENTIALS_ACTION}@v6`,
    '      - name: Update coach Lambda',
    '        run: |',
    '          aws lambda update-function-code --function-name x --publish',
    '          aws lambda update-alias --function-name x --name live',
    ...(over.prodOnly === undefined
      ? []
      : [
          '      - name: Production-only step',
          "        if: steps.env.outputs.is_prod == 'true'",
          `        run: aws lambda ${over.prodOnly} --function-name x`,
        ]),
    '',
  ].join('\n');

/// A parsed deploy role, not the HCL `role()` renders. Claim 10 reads only the
/// Environment tag off it, which is the same tag claim 4 keys blast-radius
/// separation on.
/** @param {string} env @returns {import('./check_infra_iam.mjs').DeployRole} */
const deployRole = (env) => ({
  label: `deploy_${env}`,
  name: `threkir-web-deploy-${env}`,
  envToken: env,
  providerRef: 'github',
  action: 'sts:AssumeRoleWithWebIdentity',
  operators: ['StringEquals'],
  claims: new Map(),
});

/** @param {{ prod?: string[], preview?: string[] }} grants */
const lambdaStack = (grants) => ({
  provider: null,
  providerLabel: null,
  roles: [deployRole('prod'), deployRole('preview')],
  policies: [
    ...(grants.prod === undefined
      ? []
      : [
          {
            roleLabel: 'deploy_prod',
            statements: [
              { sid: 'LambdaUpdate', effect: 'Allow', actions: grants.prod, resources: [] },
            ],
          },
        ]),
    ...(grants.preview === undefined
      ? []
      : [
          {
            roleLabel: 'deploy_preview',
            statements: [
              { sid: 'LambdaUpdate', effect: 'Allow', actions: grants.preview, resources: [] },
            ],
          },
        ]),
  ],
});

const BOTH = ['lambda:UpdateFunctionCode', 'lambda:UpdateAlias'];
const scanOf = (/** @type {string} */ text) =>
  scanWorkflowLambdaActions([{ name: 'w.yml', text }]);

test('a CLI verb maps to the one IAM action its operation is named for', () => {
  // `--publish` is a member of the UpdateFunctionCode REQUEST, not a second
  // call, which is what made lambda:PublishVersion a third unused verb.
  assert.equal(iamActionForCliVerb('update-function-code'), 'UpdateFunctionCode');
  assert.equal(iamActionForCliVerb('update-alias'), 'UpdateAlias');
  assert.equal(iamActionForCliVerb('get-alias'), 'GetAlias');
});

test('the committed workflows invoke update-function-code + update-alias, against both envs', () => {
  const scan = scanWorkflowLambdaActions(readWorkflowFiles(WORKFLOW_DIR));
  assert.deepEqual([...scan.byEnv.keys()].sort(), ['preview', 'prod']);
  for (const env of ['prod', 'preview']) {
    assert.deepEqual(
      [...(scan.byEnv.get(env) ?? [])].sort(),
      ['lambda:UpdateAlias', 'lambda:UpdateFunctionCode'],
      env,
    );
  }
  assert.deepEqual(scan.unattributed, []);
});

test('a verb only MENTIONED in a run-body comment is not an invocation', () => {
  const text = twoEnvWorkflow().replace(
    '          aws lambda update-function-code --function-name x --publish',
    '          # bin/lambda-alias-sync.sh runs aws lambda get-alias under the operator profile\n' +
      '          aws lambda update-function-code --function-name x --publish',
  );
  assert.deepEqual([...(scanOf(text).byEnv.get('prod') ?? [])].sort(), BOTH.slice().sort());
});

test('the committed roles grant exactly what the pipeline invokes against each env', () => {
  const { errors, ok } = checkLambdaActionScope(
    parseOidcStack(readFileSync(OIDC_FILE, 'utf-8')),
    scanWorkflowLambdaActions(readWorkflowFiles(WORKFLOW_DIR)),
  );
  assert.deepEqual(errors, []);
  assert.equal(ok.length, 3, ok.join('\n'));
});

// ── the per-environment derivation, on the input today's workflows cannot
//    produce. Without a synthetic disagreement the stronger derivation and the
//    repo-wide union pass on identical input, and the strengthening is a claim
//    rather than a demonstration (decisions § 1110).

test('a verb only the production leg runs is attributed to prod alone', () => {
  const scan = scanOf(twoEnvWorkflow({ prodOnly: 'publish-version' }));
  assert.deepEqual(
    [...(scan.byEnv.get('prod') ?? [])].sort(),
    ['lambda:PublishVersion', 'lambda:UpdateAlias', 'lambda:UpdateFunctionCode'],
  );
  assert.deepEqual([...(scan.byEnv.get('preview') ?? [])].sort(), BOTH.slice().sort());
  // The union the guard used to compare BOTH roles against.
  const union = new Set([...scan.byEnv.values()].flatMap((v) => [...v]));
  assert.ok(union.has('lambda:PublishVersion'));
  assert.ok(!scan.byEnv.get('preview')?.has('lambda:PublishVersion'));
});

test('the preview role passes without a verb only production invokes', () => {
  const scan = scanOf(twoEnvWorkflow({ prodOnly: 'publish-version' }));
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: [...BOTH, 'lambda:PublishVersion'], preview: BOTH }),
    scan,
  );
  assert.deepEqual(errors, []);
});

test('and the same input makes the preview role FAIL if it holds that verb', () => {
  // The over-grant the repo-wide union could never see: standing privilege on
  // an environment whose own release never issues the call.
  const scan = scanOf(twoEnvWorkflow({ prodOnly: 'publish-version' }));
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: [...BOTH, 'lambda:PublishVersion'], preview: [...BOTH, 'lambda:PublishVersion'] }),
    scan,
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /deploy_preview .* grants lambda:PublishVersion, which no workflow invokes against preview/);
});

test('a production role missing the verb only production invokes still fails', () => {
  const scan = scanOf(twoEnvWorkflow({ prodOnly: 'publish-version' }));
  const { errors } = checkLambdaActionScope(lambdaStack({ prod: BOTH, preview: BOTH }), scan);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /missing lambda:PublishVersion, which a workflow invokes against prod/);
});

test('an unexercised verb fails and is named, per environment', () => {
  const scan = scanOf(twoEnvWorkflow());
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: [...BOTH, 'lambda:GetFunction'], preview: BOTH }),
    scan,
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /grants lambda:GetFunction, which no workflow invokes against prod/);
});

test('a verb the pipeline needs but the role lacks fails the other way', () => {
  // The direction that breaks a release rather than widening one.
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: ['lambda:UpdateFunctionCode'], preview: BOTH }),
    scanOf(twoEnvWorkflow()),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /missing lambda:UpdateAlias/);
});

test('reading no invocation at all is reported, not treated as a clean set', () => {
  const { errors, ok } = checkLambdaActionScope(
    lambdaStack({ prod: ['lambda:UpdateAlias'] }),
    scanOf('jobs:\n  build:\n    steps:\n      - run: echo hi\n'),
  );
  assert.equal(ok.length, 0);
  assert.match(errors[0], /would have been compared against nothing/);
});

test('a policy with no lambda statement is reported', () => {
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: ['s3:PutObject'], preview: ['s3:PutObject'] }),
    scanOf(twoEnvWorkflow()),
  );
  assert.ok(errors.some((e) => /no statement granting any `lambda:` action/.test(e)));
});

test('an environment a workflow deploys to with no role granting it fails', () => {
  const { errors } = checkLambdaActionScope(
    lambdaStack({ prod: BOTH }),
    scanOf(twoEnvWorkflow()),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /against the preview environment, for which no deploy role grants/);
});

test('a role with no Environment tag has no environment to be compared against', () => {
  const stack = lambdaStack({ prod: BOTH, preview: BOTH });
  stack.roles[0].envToken = null;
  const { errors } = checkLambdaActionScope(stack, scanOf(twoEnvWorkflow()));
  assert.ok(errors.some((e) => /carries no Environment tag/.test(e)));
});

test('an aws lambda verb under an assumed role naming no ARN Secret is unattributed, not dropped', () => {
  const text = twoEnvWorkflow()
    .replace('          ARN_PROD: ${{ secrets.AWS_DEPLOY_ROLE_ARN_PROD }}\n', '')
    .replace('          ARN_PREVIEW: ${{ secrets.AWS_DEPLOY_ROLE_ARN_PREVIEW }}\n', '');
  const scan = scanOf(text);
  assert.equal(scan.unattributed.length, 1);
  const { errors } = checkLambdaActionScope(lambdaStack({ prod: BOTH, preview: BOTH }), scan);
  assert.ok(errors.some((e) => /which environment it deploys to could not be read/.test(e)));
});

test('an aws lambda verb in a job that assumes no role is reported, not attributed', () => {
  const text = twoEnvWorkflow().replace(`      - uses: ${CREDENTIALS_ACTION}@v6\n`, '');
  const scan = scanOf(text);
  assert.equal(scan.byEnv.size, 0);
  assert.equal(scan.uncredentialed.length, 1);
  assert.match(scan.uncredentialed[0], /Update coach Lambda/);
});

test('jobRegions splits a workflow at its two-space job keys', () => {
  const regions = jobRegions(twoEnvWorkflow());
  assert.deepEqual([...regions.keys()], ['release']);
  assert.ok(regions.get('release')?.includes('AWS_DEPLOY_ROLE_ARN_PROD'));
});

test('parseBranchOutputs keeps every output of the branch, not just env=', () => {
  const outputs = parseBranchOutputs(twoEnvWorkflow());
  assert.deepEqual(outputs.get('env'), { whenTrue: 'prod', whenFalse: 'preview' });
  assert.deepEqual(outputs.get('is_prod'), { whenTrue: 'true', whenFalse: 'false' });
});

test('envsForCondition reads both operators and gives up on anything else', () => {
  const outputs = parseBranchOutputs(twoEnvWorkflow());
  assert.deepEqual(envsForCondition("steps.env.outputs.is_prod == 'true'", outputs), ['prod']);
  assert.deepEqual(envsForCondition("steps.env.outputs.is_prod != 'true'", outputs), ['preview']);
  assert.deepEqual(envsForCondition("steps.env.outputs.env == 'preview'", outputs), ['preview']);
  // Not narrowable: attributing to both can only over-demand a grant.
  assert.equal(envsForCondition('always()', outputs), null);
  assert.equal(envsForCondition(null, outputs), null);
});

test('a declared exemption nothing grants fails, and the live map is empty', () => {
  assert.equal(UNEXERCISED_LAMBDA_ACTIONS.size, 0);
  const saved = new Map(UNEXERCISED_LAMBDA_ACTIONS);
  UNEXERCISED_LAMBDA_ACTIONS.set('lambda:GetFunction', 'kept for a reason nobody wrote down');
  try {
    const { errors } = checkLambdaActionScope(
      lambdaStack({ prod: BOTH, preview: BOTH }),
      scanOf(twoEnvWorkflow()),
    );
    assert.equal(errors.length, 1);
    assert.match(errors[0], /declares lambda:GetFunction .* but no role grants it/);
  } finally {
    UNEXERCISED_LAMBDA_ACTIONS.clear();
    for (const [k, v] of saved) UNEXERCISED_LAMBDA_ACTIONS.set(k, v);
  }
});
