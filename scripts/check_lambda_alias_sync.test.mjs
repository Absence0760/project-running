import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  RELEASE_FILE,
  SCRIPT_FILE,
  TERRAFORM_FILE,
  compareSources,
  parseReleaseWorkflow,
  parseSyncScript,
  parseTerraform,
} from './check_lambda_alias_sync.mjs';

// ─────────────────────────────── fixtures ───────────────────────────────
//
// Structurally faithful rather than minimal: the interpolated prefix, the
// nested `environment { variables { … } }` block, and a comment carrying an
// unbalanced brace are all things the real module has and all things a naive
// brace scan gets wrong.

/**
 * @param {string[][]} fns
 * @param {string[][]} aliases
 * @param {string} [prefix]
 */
function fakeTerraform(fns, aliases, prefix = 'threkir-web-${var.env}') {
  const head = `locals {\n  resource_prefix = "${prefix}"\n}\n\n`;
  const funcs = fns
    .map(
      ([label, suffix]) =>
        `# A comment whose stray brace { must not unbalance the scan.\n` +
        `resource "aws_lambda_function" "${label}" {\n` +
        `  function_name = "\${local.resource_prefix}-${suffix}"\n` +
        `  environment {\n    variables = {\n      FOO = "bar"\n    }\n  }\n` +
        `}\n`,
    )
    .join('\n');
  const als = aliases
    .map(
      ([label, fnLabel, aliasName = 'live']) =>
        `resource "aws_lambda_alias" "${label}" {\n` +
        `  name             = "${aliasName}"\n` +
        `  function_name    = aws_lambda_function.${fnLabel}.function_name\n` +
        `  function_version = aws_lambda_function.${fnLabel}.version\n` +
        `  lifecycle {\n    ignore_changes = [function_version]\n  }\n` +
        `}\n`,
    )
    .join('\n');
  return head + funcs + '\n' + als;
}

/**
 * @param {string[]} functions
 * @param {string} [prefix]
 */
function fakeScript(functions, prefix = 'threkir-web-${ENV_NAME}') {
  return (
    `#!/usr/bin/env bash\nset -euo pipefail\n\n` +
    `FUNCTIONS=(${functions.join(' ')})\n\n` +
    `for fn in "\${FUNCTIONS[@]}"; do\n` +
    `\tNAME="${prefix}-\${fn}"\n` +
    `\tCURRENT=$(aws lambda get-alias \\\n` +
    `\t\t--function-name "$NAME" \\\n` +
    `\t\t--name live \\\n` +
    `\t\t--query FunctionVersion --output text)\n` +
    `\taws lambda update-alias \\\n` +
    `\t\t--function-name "$NAME" \\\n` +
    `\t\t--name live \\\n` +
    `\t\t--function-version "$NEWEST" >/dev/null\n` +
    `done\n`
  );
}

/**
 * @param {string[][]} entries
 * @param {string} [prefix]
 */
function fakeRelease(entries, prefix = 'threkir-web-${ENV}') {
  const resolve =
    `      - name: Resolve target resources\n        id: aws\n        run: |\n` +
    `          echo "bucket=${prefix}-site" >> "$GITHUB_OUTPUT"\n` +
    entries
      .map(
        ([key, suffix]) =>
          `          echo "${key}=${prefix}-${suffix}" >> "$GITHUB_OUTPUT"\n`,
      )
      .join('');
  const steps = entries
    .map(
      ([key, suffix]) =>
        `      - name: Update ${suffix} Lambda\n        run: |\n` +
        `          NEW_VERSION=$(aws lambda update-function-code \\\n` +
        `            --function-name "\${{ steps.aws.outputs.${key} }}" \\\n` +
        `            --publish --query Version --output text)\n` +
        `          aws lambda update-alias \\\n` +
        `            --function-name "\${{ steps.aws.outputs.${key} }}" \\\n` +
        `            --name live \\\n` +
        `            --function-version "$NEW_VERSION"\n`,
    )
    .join('\n');
  return resolve + '\n' + steps;
}

// The aligned baseline every mutation below diverges from.
const FNS = [
  ['coach', 'coach'],
  ['share_run', 'share-run'],
  ['generate_route', 'generate-route'],
];
const ALIASES = [
  ['live', 'coach'],
  ['share_run_live', 'share_run'],
  ['generate_route_live', 'generate_route'],
];
const SUFFIXES = ['coach', 'share-run', 'generate-route'];
const RELEASE = [
  ['lambda', 'coach'],
  ['share_run_lambda', 'share-run'],
  ['generate_route_lambda', 'generate-route'],
];

/**
 * @param {string} tf
 * @param {string} sh
 * @param {string} rel
 */
const verdict = (tf, sh, rel) =>
  compareSources(
    parseTerraform(tf),
    parseSyncScript(sh),
    parseReleaseWorkflow(rel),
  );

/** @param {{ tf?: string, sh?: string, rel?: string }} [over] */
const aligned = (over = {}) =>
  verdict(
    over.tf ?? fakeTerraform(FNS, ALIASES),
    over.sh ?? fakeScript(SUFFIXES),
    over.rel ?? fakeRelease(RELEASE),
  );

// ──────────────────────────────── the real files ────────────────────────

test('the real Terraform, sync script and release workflow agree', () => {
  const tf = parseTerraform(readFileSync(TERRAFORM_FILE, 'utf-8'));
  const { errors, ok } = compareSources(
    tf,
    parseSyncScript(readFileSync(SCRIPT_FILE, 'utf-8')),
    parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8')),
  );
  assert.deepEqual(errors, []);
  // Not a hardcoded 8: the count comes from Terraform, so adding a Lambda
  // moves it without this assertion needing an edit.
  assert.equal(ok.length, tf.aliases.length);
  assert.ok(tf.aliases.length > 0);
});

test('every real alias resolves through to a function name', () => {
  const tf = parseTerraform(readFileSync(TERRAFORM_FILE, 'utf-8'));
  for (const a of tf.aliases) {
    assert.equal(a.aliasName, 'live', `alias ${a.label}`);
    assert.ok(a.functionName, `alias ${a.label} resolved no function name`);
  }
});

// ──────────────────────────────── parsing ───────────────────────────────

test('the HCL reader pairs aliases by reference, not by declaration order', () => {
  // Reversed alias order: a positional parse would pair every alias with the
  // wrong function, which is the class of mistake this guard exists to reject.
  const tf = parseTerraform(fakeTerraform(FNS, [...ALIASES].reverse()));
  const byLabel = new Map(tf.aliases.map((a) => [a.label, a]));
  const live = byLabel.get('live');
  const generateRoute = byLabel.get('generate_route_live');
  assert.ok(live, 'no alias labelled "live" was parsed');
  assert.ok(generateRoute, 'no alias labelled "generate_route_live" was parsed');
  assert.equal(live.functionName, 'threkir-web-<env>-coach');
  assert.equal(generateRoute.functionName, 'threkir-web-<env>-generate-route');
  assert.equal(tf.aliases.length, 3);
});

test('the sync-script parser reads the array, the loop and the alias name', () => {
  const sh = parseSyncScript(fakeScript(SUFFIXES));
  assert.deepEqual(sh.functions, SUFFIXES);
  assert.equal(sh.loopVar, 'fn');
  assert.equal(sh.templateVar, 'fn');
  assert.equal(sh.prefix, 'threkir-web-<env>');
  assert.deepEqual([...sh.aliasNames], ['live']);
});

test('the release parser ignores step outputs no update-alias references', () => {
  // `bucket=` has the same shape as a Lambda name and must not be counted.
  const rel = parseReleaseWorkflow(fakeRelease(RELEASE));
  assert.equal(rel.entries.length, 3);
  assert.ok(rel.outputs.has('bucket'));
  assert.deepEqual(
    rel.entries.map((e) => e.functionName),
    [
      'threkir-web-<env>-coach',
      'threkir-web-<env>-share-run',
      'threkir-web-<env>-generate-route',
    ],
  );
});

// ─────────────────────────────── comparison ─────────────────────────────

test('aligned sources pass with no errors and no warnings', () => {
  const { errors, warnings, ok } = aligned();
  assert.deepEqual(errors, []);
  assert.deepEqual(warnings, []);
  assert.equal(ok.length, 3);
});

test('a Lambda added to Terraform but not to the script fails, naming it', () => {
  // The exact latent defect: a ninth Lambda lands in the module and the
  // hand-maintained bash array is silently one short.
  const { errors } = aligned({
    tf: fakeTerraform(
      [...FNS, ['share_badge', 'share-badge']],
      [...ALIASES, ['share_badge_live', 'share_badge']],
    ),
  });
  const script = errors.filter((e) => /never repoints it/.test(e));
  assert.equal(script.length, 1);
  assert.match(script[0], /aws_lambda_alias\."share_badge_live"/);
  assert.match(script[0], /threkir-web-<env>-share-badge/);
  assert.match(script[0], /Fix: add "share-badge" to the FUNCTIONS array/);
  assert.match(script[0], /§ 433/);
});

test('a stale entry in the script fails, naming it', () => {
  const { errors } = aligned({ sh: fakeScript([...SUFFIXES, 'share-badge']) });
  const stale = errors.filter((e) => /^bin\/lambda-alias-sync\.sh lists /.test(e));
  assert.equal(stale.length, 1);
  assert.match(stale[0], /lists "share-badge"/);
  assert.match(stale[0], /Fix: drop "share-badge" from the FUNCTIONS array/);
});

test('a Lambda the release workflow never deploys fails, naming it', () => {
  const { errors } = aligned({
    rel: fakeRelease(RELEASE.slice(0, 2)),
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /never deploys or repoints it/);
  assert.match(errors[0], /generate_route_live/);
});

test('a release step for a Lambda Terraform does not declare fails', () => {
  const { errors } = aligned({
    rel: fakeRelease([...RELEASE, ['share_badge_lambda', 'share-badge']]),
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /release-web\.yml repoints "threkir-web-<env>-share-badge"/);
  assert.match(errors[0], /steps\.aws\.outputs\.share_badge_lambda/);
});

test('a renamed alias fails on the alias name, not on the function set', () => {
  const { errors } = aligned({
    tf: fakeTerraform(FNS, [
      ['live', 'coach', 'serving'],
      ...ALIASES.slice(1),
    ]),
  });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /do not agree on the alias name/);
  assert.match(errors[0], /Terraform declares: serving, live/);
  assert.match(errors[0], /the sync script asks for: live/);
});

// The alias-name comparison is a set union across the three sources, so a
// source that states no name drops out of it silently and the remaining two
// agree with each other. Each of the three must therefore be made to speak.

test('a Terraform alias with no literal name is loud, not silently dropped', () => {
  const tf = fakeTerraform(FNS, ALIASES).replace(
    'name             = "live"',
    'name             = var.alias_name',
  );
  const { errors } = aligned({ tf });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /aws_lambda_alias\."live" sets no literal/);
  assert.match(errors[0], /never noticed/);
});

test('a release step that passes no --name is loud', () => {
  const rel = fakeRelease(RELEASE).replace('            --name live \\\n', '');
  const { errors } = aligned({ rel });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /passes no `--name`/);
});

test('a sync script that names no alias is loud', () => {
  const sh = fakeScript(SUFFIXES).replaceAll('\t\t--name live \\\n', '');
  const { errors } = aligned({ sh });
  assert.equal(errors.length, 1);
  assert.match(errors[0], /names no alias/);
});

test('a prefix rename reports once, not once per function', () => {
  const { errors } = aligned({ sh: fakeScript(SUFFIXES, 'threkir-site-${ENV_NAME}') });
  const prefix = errors.filter((e) => /do not agree on the Lambda name prefix/.test(e));
  assert.equal(prefix.length, 1);
  assert.match(prefix[0], /threkir-web-<env> \(Terraform\)/);
  assert.match(prefix[0], /threkir-site-<env> \(bin\/lambda-alias-sync\.sh\)/);
});

test('an alias whose function_name is not a reference is loud, not skipped', () => {
  const tf = fakeTerraform(FNS, ALIASES).replace(
    'function_name    = aws_lambda_function.coach.function_name',
    'function_name    = local.some_other_thing',
  );
  const { errors } = aligned({ tf });
  assert.ok(errors.some((e) => /does not set/.test(e) && /"live"/.test(e)));
});

test('a loop that stopped iterating FUNCTIONS is loud', () => {
  const sh = fakeScript(SUFFIXES).replace(
    'for fn in "${FUNCTIONS[@]}"',
    'for fn in "${OTHER[@]}"',
  );
  const { errors } = aligned({ sh });
  assert.ok(errors.some((e) => /no longer loops over/.test(e)));
});

test('a name template built from the wrong variable is loud', () => {
  const sh = fakeScript(SUFFIXES).replace('-${fn}"', '-${other}"');
  const { errors } = aligned({ sh });
  assert.ok(errors.some((e) => /builds its function name from \$\{other\}/.test(e)));
});

test('a Terraform Lambda with no alias at all warns but does not fail', () => {
  const { errors, warnings } = aligned({
    tf: fakeTerraform([...FNS, ['osrm_proxy', 'osrm-proxy']], ALIASES),
  });
  assert.deepEqual(errors, []);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /aws_lambda_function\."osrm_proxy"/);
  assert.match(warnings[0], /has no aws_lambda_alias/);
});

test('a parse that reads nothing fails loudly instead of passing vacuously', () => {
  // The failure mode that would make this guard worthless: all three files
  // refactored past the regexes, every set empty, exit 0.
  const blind = compareSources(
    parseTerraform(''),
    parseSyncScript(''),
    parseReleaseWorkflow(''),
  );
  assert.equal(blind.ok.length, 0);
  assert.ok(blind.errors.length >= 3);
  assert.ok(blind.errors.some((e) => /Parsed no aws_lambda_alias resources/.test(e)));
  assert.ok(blind.errors.some((e) => /Parsed no FUNCTIONS entries/.test(e)));
  assert.ok(
    blind.errors.some((e) => /Parsed no `aws lambda update-alias` steps/.test(e)),
  );
  assert.ok(blind.errors.some((e) => /blind to the alias being renamed/.test(e)));
});

test('one source going blind on its own still fails', () => {
  // The subtler vacuity: only the Terraform parse breaks, so the other two
  // agree with each other and a set comparison alone would report nothing.
  const { errors, ok } = aligned({ tf: '' });
  assert.equal(ok.length, 0);
  assert.ok(errors.some((e) => /Parsed no aws_lambda_alias resources/.test(e)));
  // Both downstream sources are now orphaned against an empty Terraform, and
  // each says so in its own words rather than one swallowing the other.
  assert.equal(
    errors.filter((e) => /^bin\/lambda-alias-sync\.sh lists /.test(e)).length,
    3,
  );
  assert.equal(
    errors.filter((e) => /^release-web\.yml repoints /.test(e)).length,
    3,
  );
});

// ─────────────────── decisions § 773 — first-match-wins ───────────────────

// The filed reproduction, verbatim: a script that sets FUNCTIONS per
// environment parsed as the FIRST array alone and reported the second Lambda
// "synced and deployed" on a branch that never repoints it.
/**
 * @param {string[]} prod
 * @param {string[]} preview
 */
const perEnvScript = (prod, preview) =>
  `#!/usr/bin/env bash\nset -euo pipefail\n\n` +
  `if [[ "$ENV_NAME" == "prod" ]]; then\n` +
  `\tFUNCTIONS=(${prod.join(' ')})\n` +
  `else\n` +
  `\tFUNCTIONS=(${preview.join(' ')})\n` +
  `fi\n\n` +
  `for fn in "\${FUNCTIONS[@]}"; do\n` +
  `\tNAME="threkir-web-\${ENV_NAME}-\${fn}"\n` +
  `\taws lambda update-alias \\\n` +
  `\t\t--function-name "$NAME" \\\n` +
  `\t\t--name live \\\n` +
  `\t\t--function-version "$NEWEST" >/dev/null\n` +
  `done\n`;

test('every FUNCTIONS assignment is read, not only the first', () => {
  const sh = parseSyncScript(perEnvScript(SUFFIXES, ['coach']));
  assert.deepEqual(sh.assignments, [SUFFIXES, ['coach']]);
  assert.deepEqual(sh.functions.sort(), [...SUFFIXES].sort());
});

test('a Lambda missing from one branch’s array is not certified as synced', () => {
  const { errors, ok } = aligned({ sh: perEnvScript(SUFFIXES, ['coach']) });
  assert.deepEqual(
    ok.map((l) => l.split(' ')[0]),
    ['coach'],
  );
  const missed = errors.filter((e) => /never repoints it/.test(e));
  assert.equal(missed.length, 2);
  assert.ok(missed.every((e) => /1 of the 2 FUNCTIONS arrays \(#2\)/.test(e)));
});

test('a Lambda in every branch’s array is still certified', () => {
  const { errors, ok } = aligned({ sh: perEnvScript(SUFFIXES, SUFFIXES) });
  assert.deepEqual(errors, []);
  assert.equal(ok.length, 3);
});

test('two disagreeing NAME templates are reported rather than the first winning', () => {
  const sh = fakeScript(SUFFIXES).replace(
    'done\n',
    'NAME="threkir-web-${ENV_NAME}-legacy-${fn}"\ndone\n',
  );
  const { errors } = aligned({ sh });
  assert.ok(errors.some((e) => /builds its function name from more than one template/.test(e)));
});

// The alias name used to be read out of a 400-character window that crossed
// command boundaries, so the first `--name` in it won — here a decoy inside
// the alias call's own argument list, while the real `--name` sat past it.
test('the alias name comes from the alias call, not from a decoy inside it', () => {
  const sh =
    `FUNCTIONS=(${SUFFIXES.join(' ')})\n` +
    `for fn in "\${FUNCTIONS[@]}"; do\n` +
    `\tNAME="threkir-web-\${ENV_NAME}-\${fn}"\n` +
    `\taws lambda update-alias \\\n` +
    `\t\t--function-name "$(aws ssm get-parameter --name live --query X)" \\\n` +
    `\t\t--name stable \\\n` +
    `\t\t--function-version "$NEWEST"\n` +
    `done\n`;
  assert.deepEqual([...parseSyncScript(sh).aliasNames], ['stable']);
  const { errors } = aligned({ sh });
  assert.ok(errors.some((e) => /do not agree on the alias name/.test(e)));
});

// The same decoy written with backticks. `$( )` had been closed and this
// spelling had not: the substitution sat inside the alias call's own word list,
// so its `--name live` came before the real `--name stable` and answered for
// it. Latent because the committed script writes no backtick substitution —
// which is the only reason § 773 did not find it too.
//
// The outcome is fail-closed rather than correct, and deliberately so: an
// UNQUOTED substitution of either spelling ends the command containing it, so
// the alias call reads no `--name` at all and the "names no alias" blindness
// check fires. Reading nothing is the safe half of the pair; reading the decoy
// is the half that certifies an alias the script never repoints.
test('a backtick decoy inside the alias call cannot answer for the alias name', () => {
  const sh =
    `FUNCTIONS=(${SUFFIXES.join(' ')})\n` +
    `for fn in "\${FUNCTIONS[@]}"; do\n` +
    `\tNAME="threkir-web-\${ENV_NAME}-\${fn}"\n` +
    `\taws lambda update-alias \\\n` +
    '\t\t--function-name `aws ssm get-parameter --name live --query X` \\\n' +
    `\t\t--name stable \\\n` +
    `\t\t--function-version "$NEWEST"\n` +
    `done\n`;
  const names = [...parseSyncScript(sh).aliasNames];
  assert.ok(!names.includes('live'), `the decoy answered for the alias name: ${names}`);
  const { errors } = aligned({ sh });
  assert.ok(
    errors.some((e) => /names no alias|do not agree on the alias name/.test(e)),
    `expected a loud refusal, got ${JSON.stringify(errors)}`,
  );
});

test('a backtick inside a quoted argument is part of that argument, not a command', () => {
  // The committed script's only backticks outside comments are the JMESPath
  // literals in `--query 'Versions[?Version!=`$LATEST`].[Version]'`, and
  // reading those as a command boundary would truncate the call around them.
  const live = parseSyncScript(readFileSync(SCRIPT_FILE, 'utf-8'));
  assert.deepEqual([...live.aliasNames], ['live']);
});

test('quoting an alias name is not a disagreement', () => {
  const sh = fakeScript(SUFFIXES).replaceAll('--name live', '--name "live"');
  assert.deepEqual([...parseSyncScript(sh).aliasNames], ['live']);
  assert.deepEqual(aligned({ sh }).errors, []);
});

// Measured while fixing it: the committed script has one flat array, so the
// misread was latent — which has to be a measurement rather than a claim.
test('the committed sync script carries exactly one FUNCTIONS assignment', () => {
  const sh = parseSyncScript(readFileSync(SCRIPT_FILE, 'utf-8'));
  assert.equal(sh.assignments.length, 1);
  assert.equal(sh.templates.length, 1);
  assert.deepEqual([...sh.aliasNames], ['live']);
});
