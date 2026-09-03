#!/usr/bin/env node
// Guardrail: the IAM rails under infra/ say what the pipeline needs and
// nothing wider, and the two halves of the OIDC trust contract move together.
//
// infra/github-oidc/ mints the only two AWS identities anything outside this
// account can assume. Their trust policies are the highest-value lines in the
// Terraform tree: `token.actions.githubusercontent.com:sub` is what stops a
// job in another repository — or a pull_request build in this one, or a fork —
// from requesting the production deploy role. Nothing read those lines. The
// file's own header records that the halves have already come apart once: the
// web@1.0.3 release failed AssumeRoleWithWebIdentity when the deploy jobs
// started declaring GitHub environments while the trust policies still matched
// the old `refs/tags/web@*` ref shape. That header ends "the two halves must
// move together", which is a rule stated in prose and enforced by nothing —
// the § 439 shape.
//
// What is checked, and why each one is worth a job:
//
//   1. Trust shape. `StringEquals` on both `:aud` and `:sub`; a `:sub` with no
//      wildcard in it, anchored to `var.github_repo`, naming a GitHub
//      ENVIRONMENT rather than a ref. `StringLike` with a trailing `*` is the
//      canonical way this goes wrong, and it is one character from correct.
//   2. Environment lockstep. The set of environments the trust policies accept
//      equals the set release-web.yml can declare, and the role a tag-triggered
//      run assumes is the role whose resources are the production ones. This is
//      the half that broke.
//   3. No wildcard grant. No `Action` ending in `:*`, and `Resource = "*"` only
//      for actions AWS models no resource for — declared here with a reason,
//      and an exemption nothing uses fails as loudly as a missing one.
//   4. Blast-radius separation. Every resource ARN in a role's policy carries
//      that role's own environment token. A copy-pasted `prod` in the preview
//      role would hand every push-to-main preview deploy write access to the
//      production bucket, and the policy would still read as two tidy blocks.
//   5. Lambda coverage. The eight Lambda ARNs in each deploy policy are a
//      fourth hand-maintained transcription of the module's function list, next
//      to the three check_lambda_alias_sync.mjs already compares. A ninth
//      function reaches Terraform, the sync script and the release workflow and
//      then fails at `aws lambda update-function-code` with AccessDenied,
//      mid-release, against production.
//   6. Origin reachability. Every Lambda Function URL is AWS_IAM-authed and
//      carries BOTH CloudFront grants — `lambda:InvokeFunctionUrl` AND plain
//      `lambda:InvokeFunction`. Issue #590 measured what one grant alone does:
//      the URL 403s before invocation and the distribution's SPA error fallback
//      rewrites that 403 into the shell at 200, so the surface reads healthy
//      while the function never runs.
//
//   7. Alias lockstep. Each Function URL is created ON the function's `live`
//      alias, and a Lambda resource policy is attached per qualifier — so a
//      grant written without the alias qualifier covers the unqualified ARN and
//      not the one CloudFront invokes. That is #590's failure exactly, one
//      field over, and it fails the same invisible way. The parser also
//      declares how many blocks it SKIPPED: a Function URL written so the
//      function-name regex misses it is one whose auth type nothing reads, and
//      a smaller loop looks identical to a smaller stack.
//
//   8. Secret scope. No Lambda environment merges the decrypted sops map whole.
//      A key added to the file for one function otherwise reaches every
//      function whose env takes the bag, which is the same over-grant as a
//      wildcard Action and is invisible in exactly the same way — the
//      Terraform reads as one tidy `merge(...)` line either way.
//
//   9. Decrypt-grant justification. The env's secrets CMK is the one key in the
//      account whose loss is unrecoverable, and its decrypt statement is where
//      a principal quietly accumulates. Both env roots now leave
//      `kms_decrypt_principal_arn` at "" — the GitHub deploy role is NOT a
//      decrypt principal — and that is only correct while two premises hold,
//      neither of which is stated anywhere a change would trip over:
//      no CREDENTIALED workflow job runs `terraform` (so nothing in CI ever
//      reaches `data.sops_file`), and no `aws_lambda_function` sets
//      `kms_key_arn` (so `lambda:GetFunction` / `UpdateFunctionCode` from the
//      deploy role never transits this key). The check runs BOTH ways: a
//      non-empty wire while both premises hold is standing privilege, and an
//      empty wire once either premise breaks is a release that fails with
//      AccessDenied against production, mid-deploy. decisions § 1021.
//
//      The workflow scan reads `.github/workflows/*.yml` and nothing else,
//      because a composite action's `runs.steps` is a different shape and
//      needs a second parser. Rather than leave that as a silent blind spot,
//      the claim asserts what makes it safe: no composite action under
//      .github/actions/ assumes an AWS role. The day one does, this fails and
//      says to widen the scan — which is the only outcome that cannot be a
//      false negative about a credentialed terraform run nobody read.
//
// Offline by design: no AWS credentials, no `terraform init`. Nothing here is
// transcribed — every name, every environment, every function suffix and every
// workflow job is read out of one of the sources, which are the github-oidc
// stack and its variables, the web-stack module, the two env roots, and every
// workflow under .github/workflows/.
//
// Run: `node scripts/check_infra_iam.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list — a guard nothing runs enforces
//      nothing.
// Unit tests: `node --test scripts/check_infra_iam.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseSteps, runBody } from './check_ci_diagnostics.mjs';
import {
  blockEnd,
  hclBlocks,
  hclResources,
  nestedBlock,
  nestedBlocks,
  stripComments,
} from './hcl_lex.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at
// mutated copies of the sources, which is how a guard is shown to fail.
export const OIDC_FILE =
  process.env.INFRA_IAM_OIDC ?? join(REPO_ROOT, 'infra/github-oidc/main.tf');
export const OIDC_VARS_FILE =
  process.env.INFRA_IAM_OIDC_VARS ??
  join(REPO_ROOT, 'infra/github-oidc/variables.tf');
export const MODULE_FILE =
  process.env.INFRA_IAM_MODULE ??
  join(REPO_ROOT, 'infra/modules/web-stack/main.tf');
export const RELEASE_FILE =
  process.env.INFRA_IAM_RELEASE ??
  join(REPO_ROOT, '.github/workflows/release-web.yml');

/// The two env roots that call the web-stack module, and the workflow
/// directory. Claim 9 reads the wire on one side and the pipeline on the
/// other; both have to be sources rather than assumptions, or the guard is
/// just the sentence it replaced.
export const ENV_FILES =
  process.env.INFRA_IAM_ENVS?.split(',') ??
  ['prod', 'preview'].map((e) => join(REPO_ROOT, `infra/envs/${e}/main.tf`));
export const WORKFLOW_DIR =
  process.env.INFRA_IAM_WORKFLOWS ?? join(REPO_ROOT, '.github/workflows');
export const ACTION_DIR =
  process.env.INFRA_IAM_ACTIONS ?? join(REPO_ROOT, '.github/actions');

/// The action every credentialed job in this repo assumes a role through. A
/// job without it holds no AWS identity at all, so its `terraform` — which is
/// what terraform.yml runs on every PR — cannot reach KMS whatever it says.
export const CREDENTIALS_ACTION = 'aws-actions/configure-aws-credentials';

/// The GitHub OIDC issuer and the audience AWS's STS expects. Both are fixed
/// by the two providers, not by us — a stack naming anything else is not
/// talking to GitHub Actions.
export const OIDC_ISSUER = 'https://token.actions.githubusercontent.com';
export const OIDC_AUDIENCE = 'sts.amazonaws.com';
export const CLAIM_PREFIX = 'token.actions.githubusercontent.com';

/// The same prefix as a regex-safe literal. Spelled out rather than escaped at
/// the use site: the dots are metacharacters, and an escape applied by a call
/// is one a reader (and a scanner) has to notice to trust the pattern.
export const CLAIM_PREFIX_PATTERN = 'token\\.actions\\.githubusercontent\\.com';

/// Actions granted on `Resource: "*"` because AWS models no resource for them,
/// each with the reason. An action on `*` that is absent from this map fails;
/// an entry here that no statement uses fails too, because a stale exemption
/// reads as a deliberate decision long after the grant it excused is gone.
export const RESOURCELESS_ACTIONS = new Map([
  [
    'cloudfront:CreateInvalidation',
    'IAM does not match distribution ARNs for this action — AWS enforces account isolation only',
  ],
  [
    'cloudfront:ListDistributions',
    'a list action has no resource to scope to; the release workflow resolves the distribution id by alias',
  ],
]);

/**
 * @typedef {{ sid: string | null, effect: string | null, actions: string[], resources: string[] }} Statement
 * @typedef {{ label: string, name: string | null, envToken: string | null, providerRef: string | null,
 *             action: string | null, operators: string[], claims: Map<string, string> }} DeployRole
 * @typedef {{ roleLabel: string | null, statements: Statement[] }} RolePolicy
 * @typedef {{ issuer: string | null, audiences: string[] }} OidcProvider
 * @typedef {{ provider: OidcProvider | null, providerLabel: string | null, roles: DeployRole[],
 *             policies: RolePolicy[] }} OidcStack
 * @typedef {{ predicate: string | null, whenTrue: string | null, whenFalse: string | null }} Branch
 * @typedef {{ environment: Branch, resourceEnv: Branch }} ReleaseWorkflow
 * @typedef {{ authType: string | null, qualifier: string | null }} FunctionUrl
 * @typedef {{ fn: string | null, action: string | null, principal: string | null,
 *             sourceArn: string | null, qualifier: string | null }} InvokeGrant
 * @typedef {{ label: string, name: string | null, fn: string | null }} FunctionAlias
 * @typedef {{ local: string, filter: string | null }} SecretMerge
 * @typedef {{ found: boolean, identifiers: string[], cmkEnvFunctions: string[], statements: number }} KmsDecryptGrant
 * @typedef {{ file: string, job: string, credentialed: boolean, terraform: boolean, steps: number }} WorkflowJob
 * @typedef {{ prefix: string | null, functions: Map<string, string>, urls: Map<string, FunctionUrl>,
 *             aliases: Map<string, FunctionAlias>, permissions: InvokeGrant[],
 *             secretMerges: SecretMerge[],
 *             declared: { urls: number, permissions: number } }} WebStack
 */

// ───────────────────────────── value readers ─────────────────────────────

/// Every double-quoted string assigned to `key`, whether the assignment is one
/// scalar (`Resource = "*"`) or a list. Returns null when the key is absent, so
/// a caller can tell "no Resource clause" from "an empty one".
/**
 * @param {string} body already comment-stripped
 * @param {string} key
 * @returns {string[] | null}
 */
export function stringsFor(body, key) {
  const re = new RegExp(`(?:^|[\\s{,])${key}\\s*=\\s*`, 'm');
  const m = body.match(re);
  if (!m || m.index === undefined) return null;
  const rest = body.slice(m.index + m[0].length);
  if (rest.startsWith('"')) {
    const one = rest.match(/^"([^"]*)"/);
    return one ? [one[1]] : [];
  }
  if (!rest.startsWith('[')) return [];
  const close = matchingBracket(rest, 0);
  if (close < 0) return [];
  return [...rest.slice(1, close).matchAll(/"([^"]*)"/g)].map((x) => x[1]);
}

/// Index of the `]` closing the `[` at `open`, or -1. Brackets inside strings
/// do not count.
/**
 * @param {string} src
 * @param {number} open
 * @returns {number}
 */
export function matchingBracket(src, open) {
  let depth = 0;
  let inString = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === '[') depth++;
    else if (c === ']') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/// Every `{ … }` element of the `Statement = [ … ]` array in one jsonencode'd
/// policy body, read as `{sid, effect, actions, resources}`.
/**
 * @param {string} policyBody already comment-stripped
 * @returns {Statement[]}
 */
export function parseStatements(policyBody) {
  const head = policyBody.match(/Statement\s*=\s*\[/);
  if (!head || head.index === undefined) {
    // A single-statement policy writes `Statement = [{ … }]` in this repo, so a
    // missing array is a shape change worth reporting rather than absorbing.
    return [];
  }
  const open = policyBody.indexOf('[', head.index);
  const close = matchingBracket(policyBody, open);
  if (close < 0) return [];
  const inner = policyBody.slice(open + 1, close);

  /** @type {Statement[]} */
  const out = [];
  let i = 0;
  while (i < inner.length) {
    const start = inner.indexOf('{', i);
    if (start < 0) break;
    const end = braceEnd(inner, start);
    if (end < 0) break;
    const body = inner.slice(start + 1, end);
    out.push({
      sid: stringsFor(body, 'Sid')?.[0] ?? null,
      effect: stringsFor(body, 'Effect')?.[0] ?? null,
      actions: stringsFor(body, 'Action') ?? [],
      resources: stringsFor(body, 'Resource') ?? [],
    });
    i = end + 1;
  }
  return out;
}

/**
 * @param {string} src
 * @param {number} open
 * @returns {number}
 */
function braceEnd(src, open) {
  let depth = 0;
  let inString = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

// ─────────────────────────────── parsers ────────────────────────────────

/**
 * @param {string} raw
 * @returns {OidcStack}
 */
export function parseOidcStack(raw) {
  const src = stripComments(raw);

  /** @type {OidcProvider | null} */
  let provider = null;
  /** @type {string | null} */
  let providerLabel = null;
  for (const { label, body } of hclResources(
    src,
    'aws_iam_openid_connect_provider',
  )) {
    providerLabel = label;
    provider = {
      issuer: body.match(/^\s*url\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      audiences: stringsFor(body, 'client_id_list') ?? [],
    };
  }

  /** @type {DeployRole[]} */
  const roles = [];
  for (const { label, body } of hclResources(src, 'aws_iam_role')) {
    const policy = nestedBlock(
      body,
      /assume_role_policy\s*=\s*jsonencode\(\s*\{/,
    );
    /** @type {Map<string, string>} */
    const claims = new Map();
    /** @type {string[]} */
    const operators = [];
    if (policy !== null) {
      const condition = nestedBlock(policy, /Condition\s*=\s*\{/);
      if (condition !== null) {
        for (const m of condition.matchAll(
          /^\s*([A-Za-z][A-Za-z0-9:]*)\s*=\s*\{/gm,
        )) {
          operators.push(m[1]);
        }
        for (const m of condition.matchAll(
          new RegExp(
            `"${CLAIM_PREFIX_PATTERN}:([a-z_]+)"\\s*=\\s*"([^"]*)"`,
            'g',
          ),
        )) {
          claims.set(m[1], m[2]);
        }
      }
    }
    roles.push({
      label,
      name: body.match(/^\s*name\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      envToken: body.match(/Environment\s*=\s*"([^"]*)"/)?.[1] ?? null,
      providerRef:
        policy?.match(
          /Federated\s*=\s*aws_iam_openid_connect_provider\.([A-Za-z0-9_-]+)\.arn/,
        )?.[1] ?? null,
      action: policy ? (stringsFor(policy, 'Action')?.[0] ?? null) : null,
      operators,
      claims,
    });
  }

  /** @type {RolePolicy[]} */
  const policies = [];
  for (const { body } of hclResources(src, 'aws_iam_role_policy')) {
    const inline = nestedBlock(body, /policy\s*=\s*jsonencode\(\s*\{/);
    policies.push({
      roleLabel:
        body.match(/^\s*role\s*=\s*aws_iam_role\.([A-Za-z0-9_-]+)\./m)?.[1] ??
        null,
      statements: inline === null ? [] : parseStatements(inline),
    });
  }

  return { provider, providerLabel, roles, policies };
}

/// The two branches release-web.yml takes on the same `refs/tags/web@`
/// predicate: which GitHub environment the job declares, and which resource
/// environment its steps then target. Pairing them is what links a trust claim
/// to a set of ARNs.
/**
 * @param {string} src
 * @returns {ReleaseWorkflow}
 */
export function parseReleaseWorkflow(src) {
  const nameLine = src.match(
    /^\s*name:\s*\$\{\{\s*(.+?)\s*&&\s*'([^']*)'\s*\|\|\s*'([^']*)'\s*\}\}/m,
  );
  /** @type {Branch} */
  const environment = {
    predicate: nameLine?.[1] ?? null,
    whenTrue: nameLine?.[2] ?? null,
    whenFalse: nameLine?.[3] ?? null,
  };

  // The shell that decides which resource environment the run deploys to.
  // Read as its own branch rather than assumed to agree with the one above —
  // the whole point is that the two are separate statements of one fact.
  const shell = src.match(
    /if\s*\[\[\s*"\$GITHUB_REF"\s*==\s*(\S+)\s*\]\];\s*then([\s\S]*?)\n\s*else\n([\s\S]*?)\n\s*fi/,
  );
  /** @type {Branch} */
  const resourceEnv = {
    predicate: shell?.[1] ?? null,
    whenTrue: shell?.[2].match(/echo\s+"env=([a-z]+)"/)?.[1] ?? null,
    whenFalse: shell?.[3].match(/echo\s+"env=([a-z]+)"/)?.[1] ?? null,
  };

  return { environment, resourceEnv };
}

/**
 * @param {string} raw
 * @returns {WebStack}
 */
export function parseWebStack(raw) {
  const src = stripComments(raw);
  const prefix =
    src.match(/^\s*resource_prefix\s*=\s*"([^"]*)"/m)?.[1] ?? null;

  /** @type {Map<string, string>} */
  const functions = new Map();
  for (const { label, body } of hclResources(src, 'aws_lambda_function')) {
    const name = body.match(/^\s*function_name\s*=\s*"([^"]*)"/m)?.[1];
    if (name === undefined || prefix === null) continue;
    if (!name.startsWith('${local.resource_prefix}-')) continue;
    functions.set(label, name.slice('${local.resource_prefix}-'.length));
  }

  /** @type {Map<string, FunctionAlias>} */
  const aliases = new Map();
  for (const { label, body } of hclResources(src, 'aws_lambda_alias')) {
    aliases.set(label, {
      label,
      name: body.match(/^\s*name\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      fn:
        body.match(
          /^\s*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\./m,
        )?.[1] ?? null,
    });
  }

  const urlBlocks = hclResources(src, 'aws_lambda_function_url');
  /** @type {Map<string, FunctionUrl>} */
  const urls = new Map();
  for (const { body } of urlBlocks) {
    const fn = body.match(
      /^\s*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\./m,
    )?.[1];
    if (fn === undefined) continue;
    urls.set(fn, {
      authType: body.match(/^\s*authorization_type\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      qualifier: body.match(/^\s*qualifier\s*=\s*(\S+)/m)?.[1] ?? null,
    });
  }

  const permissionBlocks = hclResources(src, 'aws_lambda_permission');
  /** @type {InvokeGrant[]} */
  const permissions = [];
  for (const { body } of permissionBlocks) {
    permissions.push({
      fn:
        body.match(
          /^\s*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\./m,
        )?.[1] ?? null,
      action: body.match(/^\s*action\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      principal: body.match(/^\s*principal\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      sourceArn: body.match(/^\s*source_arn\s*=\s*(\S+)/m)?.[1] ?? null,
      qualifier: body.match(/^\s*qualifier\s*=\s*(\S+)/m)?.[1] ?? null,
    });
  }

  return {
    prefix,
    functions,
    urls,
    aliases,
    permissions,
    secretMerges: parseSecretMerges(src),
    declared: { urls: urlBlocks.length, permissions: permissionBlocks.length },
  };
}

/// Index of the `)` closing the call that opens at `open`, or -1. Parens inside
/// a double-quoted string do not count.
/**
 * @param {string} src
 * @param {number} open
 * @returns {number}
 */
function parenEnd(src, open) {
  let depth = 0;
  let inString = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/// Every place a `*_lambda_env` local reaches into the decrypted sops map, and
/// the filter — if any — standing between the map and the Lambda's
/// environment. A reference wrapped in `{ for k, v in <map> : k => v if … }`
/// admits the keys the predicate names; a bare reference admits the file.
/**
 * @param {string} src comment-stripped module source
 * @returns {SecretMerge[]}
 */
export function parseSecretMerges(src) {
  /** @type {SecretMerge[]} */
  const out = [];
  const envLocal = /^\s*([A-Za-z0-9_]*lambda_env)\s*=\s*merge\(/gm;
  let m;
  while ((m = envLocal.exec(src)) !== null) {
    const open = src.indexOf('(', m.index + m[0].length - 1);
    const close = parenEnd(src, open);
    if (close < 0) continue;
    const body = src.slice(open + 1, close);
    for (const ref of body.matchAll(/data\.sops_file\.secrets\[0\]\.data/g)) {
      const before = body.slice(0, ref.index);
      const brace = before.lastIndexOf('{');
      // `{ for k, v in ` is the only thing that may sit between the opening
      // brace and the map. Anything else — including no brace at all — is the
      // whole file arriving in the environment.
      const comprehension =
        brace >= 0 && /^\s*for\s+[A-Za-z0-9_]+\s*,\s*[A-Za-z0-9_]+\s+in\s*$/.test(before.slice(brace + 1));
      if (!comprehension) {
        out.push({ local: m[1], filter: null });
        continue;
      }
      const after = body.slice(ref.index + ref[0].length);
      const predicate = after.match(/^\s*:[^\n}]*?\bif\b([^\n}]*)/)?.[1] ?? null;
      out.push({ local: m[1], filter: predicate === null ? null : predicate.trim() });
    }
  }
  return out;
}

// ────────────────────────────── comparison ──────────────────────────────

/// The secrets CMK's decrypt statement, and whether any Lambda holds its
/// environment under that same key.
///
/// The statement is located by what it GRANTS (an AWS-principal statement whose
/// actions include `kms:Decrypt`) rather than by its Sid, because a Sid is a
/// label and renaming one must not turn this claim off silently.
/**
 * @param {string} raw the web-stack module source
 * @returns {KmsDecryptGrant}
 */
export function parseKmsDecryptGrant(raw) {
  const src = stripComments(raw);
  /** @type {string[]} */
  const identifiers = [];
  let statements = 0;
  let found = false;
  for (const doc of hclBlocks(src, 'data', 'aws_iam_policy_document')) {
    for (const st of nestedBlocks(doc.body, /(?:^|\n)\s*statement\s*\{/)) {
      statements++;
      const actions = stringsFor(st.body, 'actions') ?? [];
      if (!actions.includes('kms:Decrypt')) continue;
      const principals = nestedBlock(st.body, /(?:^|\n)\s*principals\s*\{/);
      if (principals === null) continue;
      if (!/^\s*type\s*=\s*"AWS"/m.test(principals)) continue;
      // The env's own root principal is the operator's sops path, not a
      // pipeline grant, and is out of scope for this claim.
      if (/identifiers\s*=\s*\[\s*"arn:aws:iam::\$\{[^"]*\}:root"\s*\]/.test(principals))
        continue;
      found = true;
      const list = principals.slice(principals.indexOf('['), principals.lastIndexOf(']') + 1);
      for (const m of list.matchAll(/"([^"]*)"|(var\.[A-Za-z0-9_]+)/g))
        identifiers.push(m[1] ?? m[2]);
    }
  }

  /** @type {string[]} */
  const cmkEnvFunctions = [];
  for (const { label, body } of hclResources(src, 'aws_lambda_function'))
    if (/^\s*kms_key_arn\s*=/m.test(body)) cmkEnvFunctions.push(label);

  return { found, identifiers, cmkEnvFunctions, statements };
}

/// The `kms_decrypt_principal_arn` an env root passes into the module, as the
/// literal right-hand side. `null` when the argument is absent — which is the
/// state that leaves the module default `""` in force, and is what both roots
/// do since decisions § 1021.
/**
 * @param {string} raw an `infra/envs/<env>/main.tf`
 * @returns {{ hasModuleCall: boolean, wire: string | null }}
 */
export function parseEnvWire(raw) {
  const src = stripComments(raw);
  // `module "web" {` carries ONE label, not the two hclBlocks expects.
  const re = /(?:^|\n)\s*module\s+"[A-Za-z0-9_-]+"\s*\{/g;
  let found = false;
  let m;
  while ((m = re.exec(src)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = blockEnd(src, open);
    if (close < 0) continue;
    found = true;
    const body = src.slice(open + 1, close);
    const wire = body.match(/^\s*kms_decrypt_principal_arn\s*=\s*(.+?)\s*$/m);
    if (wire) return { hasModuleCall: true, wire: wire[1] };
    re.lastIndex = close;
  }
  return { hasModuleCall: found, wire: null };
}

/// Every workflow job, tagged with whether it assumes an AWS role and whether
/// any of its `run:` steps invokes `terraform`.
///
/// A command is a terraform invocation when `terraform` is the FIRST word of a
/// `&&` / `;` / `|`-separated segment of a run line. Prose cannot satisfy that:
/// a YAML comment's first word is `#`, which is why the four `terraform apply`
/// mentions in ci.yml's and terraform.yml's own comments are not read as runs.
/**
 * @param {readonly {name: string, text: string}[]} files
 * @returns {WorkflowJob[]}
 */
export function parseWorkflowJobs(files) {
  /** @type {Map<string, WorkflowJob>} */
  const jobs = new Map();
  for (const { name, text } of files) {
    for (const step of parseSteps(text)) {
      const key = `${name}:${step.job}`;
      const job = jobs.get(key) ?? {
        file: name,
        job: step.job,
        credentialed: false,
        terraform: false,
        steps: 0,
      };
      job.steps++;
      if (step.body.includes(CREDENTIALS_ACTION)) job.credentialed = true;
      if (step.hasRun)
        for (const line of runBody(step).split('\n'))
          for (const segment of line.split(/&&|\|\||;|\|/))
            if (/^\s*(?:-\s+)?(?:run:\s*)?terraform(?:\s|$)/.test(segment))
              job.terraform = true;
      jobs.set(key, job);
    }
  }
  return [...jobs.values()];
}

/**
 * @param {string} dir
 * @returns {{ name: string, text: string }[]}
 */
export function readWorkflowFiles(dir) {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
    .sort()
    .map((name) => ({ name, text: readFileSync(join(dir, name), 'utf-8') }));
}

/// Composite actions, one `action.yml` per directory. Read only to prove none
/// of them assumes an AWS role — see the note in claim 9's header.
/**
 * @param {string} dir
 * @returns {string[]} the names of the actions that assume an AWS role
 */
export function credentialedActions(dir) {
  /** @type {string[]} */
  const found = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return found;
  }
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (!entry.isDirectory()) continue;
    for (const file of ['action.yml', 'action.yaml']) {
      let text;
      try {
        text = readFileSync(join(dir, entry.name, file), 'utf-8');
      } catch {
        continue;
      }
      if (text.includes(CREDENTIALS_ACTION)) found.push(entry.name);
    }
  }
  return found;
}

/// Claim 9. See the header.
/**
 * @param {KmsDecryptGrant} grant
 * @param {{ path: string, hasModuleCall: boolean, wire: string | null }[]} envs
 * @param {readonly WorkflowJob[]} jobs
 * @param {readonly string[]} credentialedCompositeActions
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkDecryptGrant(grant, envs, jobs, credentialedCompositeActions = []) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  if (grant.statements === 0 || !grant.found) {
    errors.push(
      'no kms:Decrypt statement with an AWS principal found in the web-stack module ' +
        `(${grant.statements} statement(s) read). Either the secrets key policy moved or this ` +
        'reader stopped matching — and a decrypt grant nothing reads is exactly what claim 9 exists ' +
        'to stop accumulating.',
    );
    return { errors, ok };
  }
  if (!grant.identifiers.includes('var.kms_decrypt_principal_arn')) {
    errors.push(
      'the module\'s kms:Decrypt statement no longer takes `var.kms_decrypt_principal_arn` in its ' +
        `identifiers (read: ${JSON.stringify(grant.identifiers)}). That variable is the one knob ` +
        'for restoring the grant the day CI needs it; without it the two halves below are comparing ' +
        'a wire against nothing.',
    );
  }
  if (envs.length === 0) {
    errors.push('no env root was read, so nothing about the decrypt wire was checked.');
    return { errors, ok };
  }
  for (const env of envs) {
    if (!env.hasModuleCall)
      errors.push(
        `${env.path} holds no \`module "web"\` block — the env root moved or this reader stopped ` +
          'matching, and its decrypt wire was not read.',
      );
  }

  const credentialedTerraform = jobs.filter((j) => j.credentialed && j.terraform);
  const needed = credentialedTerraform.length > 0 || grant.cmkEnvFunctions.length > 0;
  /** @type {string[]} */
  const because = [];
  if (credentialedTerraform.length > 0)
    because.push(
      `${credentialedTerraform.map((j) => `${j.file}:${j.job}`).join(', ')} assume(s) an AWS role AND run(s) terraform`,
    );
  if (grant.cmkEnvFunctions.length > 0)
    because.push(
      `aws_lambda_function.${grant.cmkEnvFunctions.join(', aws_lambda_function.')} set(s) kms_key_arn, so the deploy role's lambda:GetFunction / UpdateFunctionCode transits this key`,
    );

  for (const env of envs) {
    if (!env.hasModuleCall) continue;
    const wired = env.wire !== null && env.wire !== '""';
    if (needed && !wired) {
      errors.push(
        `${env.path} leaves \`kms_decrypt_principal_arn\` empty, but ${because.join(' and ')}. ` +
          'That deploy will fail with AccessDenied against the secrets CMK, mid-release. Wire the ' +
          "env's deploy role back in (decisions § 1021 removed it precisely because neither was true).",
      );
      continue;
    }
    if (!needed && wired) {
      errors.push(
        `${env.path} wires \`kms_decrypt_principal_arn = ${env.wire}\`, granting that principal ` +
          'kms:Decrypt on the key protecting ANTHROPIC_API_KEY and SUPABASE_SECRET_KEY — while no ' +
          'credentialed workflow job runs terraform and no Lambda holds its environment under this ' +
          'key. Nothing in the pipeline can exercise the grant, so it is standing privilege on the ' +
          'one key in the account whose loss is unrecoverable (decisions § 1021).',
      );
      continue;
    }
    ok.push(
      needed
        ? `${env.path}: decrypt principal wired, and the pipeline needs it (${because.join('; ')})`
        : `${env.path}: no CI decrypt principal on the secrets CMK, and nothing in the pipeline needs one`,
    );
  }

  if (credentialedCompositeActions.length > 0)
    errors.push(
      `composite action(s) ${credentialedCompositeActions.join(', ')} assume an AWS role. This ` +
        "claim's terraform scan reads .github/workflows/*.yml only — a composite action's " +
        '`runs.steps` is a different shape — so a credentialed action running terraform would go ' +
        'unread. Widen the scan before letting one hold AWS credentials.',
    );

  if (jobs.length === 0)
    errors.push(
      'no workflow job was read, so "no credentialed job runs terraform" rests on an empty scan ' +
        'rather than on the workflows.',
    );
  else if (!needed)
    ok.push(
      `${jobs.length} workflow job(s) read; ${jobs.filter((j) => j.credentialed).length} assume an ` +
        `AWS role, ${jobs.filter((j) => j.terraform).length} run terraform, none does both`,
    );

  return { errors, ok };
}

/**
 * @param {OidcStack} oidc
 * @param {ReleaseWorkflow} release
 * @param {WebStack} web
 * @param {string} oidcVars
 * @returns {{ errors: string[], ok: string[] }}
 */
export function compareSources(oidc, release, web, oidcVars) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  // ── 1. the OIDC provider itself ──
  if (oidc.provider === null) {
    errors.push(
      'no aws_iam_openid_connect_provider in the github-oidc stack — either the ' +
        'provider moved or the parser stopped matching, and either way nothing ' +
        'below was really checked.',
    );
  } else {
    if (oidc.provider.issuer !== OIDC_ISSUER) {
      errors.push(
        `OIDC provider url is ${JSON.stringify(oidc.provider.issuer)}, not ${OIDC_ISSUER} — ` +
          'a provider pointed anywhere else is not GitHub Actions.',
      );
    }
    if (
      oidc.provider.audiences.length !== 1 ||
      oidc.provider.audiences[0] !== OIDC_AUDIENCE
    ) {
      errors.push(
        `OIDC provider client_id_list is ${JSON.stringify(oidc.provider.audiences)}; it must be ` +
          `exactly ["${OIDC_AUDIENCE}"]. Every extra audience is one more token shape AWS will accept.`,
      );
    } else {
      ok.push(`OIDC provider trusts ${OIDC_ISSUER} for ${OIDC_AUDIENCE} alone`);
    }
  }

  if (oidc.roles.length === 0) {
    errors.push(
      'no aws_iam_role found in the github-oidc stack — nothing was checked.',
    );
    return { errors, ok };
  }

  // ── 2. trust-policy shape, per role ──
  /** @type {Map<string, string>} */
  const roleEnvToSub = new Map();
  const envTokens = new Set(
    oidc.roles.map((r) => r.envToken).filter((t) => t !== null),
  );

  for (const role of oidc.roles) {
    const where = `aws_iam_role.${role.label}`;
    if (role.action !== 'sts:AssumeRoleWithWebIdentity') {
      errors.push(
        `${where}: assume-role Action is ${JSON.stringify(role.action)}, not sts:AssumeRoleWithWebIdentity.`,
      );
    }
    if (role.providerRef !== oidc.providerLabel) {
      errors.push(
        `${where}: Principal.Federated is ${JSON.stringify(role.providerRef)} rather than the ` +
          `stack's own aws_iam_openid_connect_provider.${oidc.providerLabel}.`,
      );
    }
    if (role.operators.length !== 1 || role.operators[0] !== 'StringEquals') {
      errors.push(
        `${where}: trust Condition uses ${JSON.stringify(role.operators)}. It must be exactly ` +
          '["StringEquals"] — StringLike (or any Ignore-case / ForAnyValue form) turns the sub ' +
          'claim from an identity into a pattern, and a pattern is one `*` from matching a fork.',
      );
    }
    if (role.claims.get('aud') !== OIDC_AUDIENCE) {
      errors.push(
        `${where}: trust policy does not pin ${CLAIM_PREFIX}:aud to ${OIDC_AUDIENCE} ` +
          `(got ${JSON.stringify(role.claims.get('aud') ?? null)}).`,
      );
    }

    const sub = role.claims.get('sub');
    if (sub === undefined) {
      errors.push(
        `${where}: trust policy pins no ${CLAIM_PREFIX}:sub. Without it any repository on GitHub ` +
          'that can reach this provider can assume the role.',
      );
      continue;
    }
    if (/[*?]/.test(sub)) {
      errors.push(
        `${where}: sub claim ${JSON.stringify(sub)} contains a wildcard. Under StringEquals it ` +
          'matches nothing; under StringLike it matches far too much.',
      );
    }
    const shape = sub.match(
      /^repo:(\$\{var\.github_repo\}|[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+):environment:([A-Za-z0-9_-]+)$/,
    );
    if (!shape) {
      errors.push(
        `${where}: sub claim ${JSON.stringify(sub)} is not ` +
          '`repo:<owner/repo>:environment:<name>`. A ref- or pull_request-shaped sub is assumable ' +
          'by any branch or any PR build, including one opened from a fork.',
      );
      continue;
    }
    if (role.envToken === null) {
      errors.push(
        `${where}: no Environment tag, so the role's own environment cannot be read and its ` +
          'resource scoping cannot be checked against it.',
      );
      continue;
    }
    if (role.name === null || !role.name.endsWith(`-${role.envToken}`)) {
      errors.push(
        `${where}: role name ${JSON.stringify(role.name)} does not end in its Environment tag ` +
          `(-${role.envToken}). The name is what an operator reads in the console; the tag is what ` +
          'cost and access reviews group by. They must agree.',
      );
    }
    roleEnvToSub.set(role.envToken, shape[2]);
    ok.push(
      `${where}: StringEquals sub = repo:<repo>:environment:${shape[2]}, aud pinned`,
    );
  }

  // A variable with a default is a variable that can go unset without anyone
  // noticing — and this one is the repository the whole trust policy anchors to.
  const repoVar = oidcVars.match(
    /variable\s+"github_repo"\s*\{([\s\S]*?)\n\}/,
  )?.[1];
  if (repoVar === undefined) {
    errors.push(
      'infra/github-oidc/variables.tf declares no `github_repo` variable — the sub claim ' +
        'interpolates it, so the parser and the source disagree.',
    );
  } else if (/^\s*default\s*=/m.test(repoVar)) {
    errors.push(
      'infra/github-oidc/variables.tf gives `github_repo` a default. It must have none: an ' +
        'apply with the tfvars missing would then mint deploy roles trusting whatever repository ' +
        'the default names, silently.',
    );
  } else {
    ok.push('github_repo has no default — an unset apply fails rather than guesses');
  }

  // ── 3. environment lockstep with the release workflow ──
  const { environment, resourceEnv } = release;
  const branchesRead =
    environment.whenTrue !== null &&
    environment.whenFalse !== null &&
    resourceEnv.whenTrue !== null &&
    resourceEnv.whenFalse !== null;
  if (!branchesRead) {
    errors.push(
      'could not read both branches of release-web.yml — the job-level `environment: name:` ' +
        'expression and the `Determine env + version` shell. One of them has moved, and the ' +
        'lockstep that failed the web@1.0.3 release is unchecked until this parses again.',
    );
  } else {
    const linked =
      (environment.predicate ?? '').includes('refs/tags/web@') &&
      (resourceEnv.predicate ?? '').includes('refs/tags/web@');
    if (!linked) {
      errors.push(
        'the GitHub-environment branch and the resource-environment branch in release-web.yml no ' +
          'longer test the same `refs/tags/web@` predicate, so which trust claim goes with which ' +
          'set of ARNs can no longer be derived from the workflow.',
      );
    }
    const declared = new Set([environment.whenTrue, environment.whenFalse]);
    const trusted = new Set(roleEnvToSub.values());
    const missing = [...declared].filter((e) => e !== null && !trusted.has(e));
    const extra = [...trusted].filter((e) => !declared.has(e));
    if (missing.length > 0) {
      errors.push(
        `release-web.yml can declare GitHub environment(s) ${JSON.stringify(missing)} that no ` +
          'deploy role trusts — that run reaches AssumeRoleWithWebIdentity and is refused, which ' +
          'is exactly how web@1.0.3 failed.',
      );
    }
    if (extra.length > 0) {
      errors.push(
        `deploy role(s) trust GitHub environment(s) ${JSON.stringify(extra)} that release-web.yml ` +
          'never declares. A trusted environment nothing uses is a role anyone who can create that ' +
          'environment can assume.',
      );
    }
    for (const [resEnv, ghEnv] of [
      [resourceEnv.whenTrue, environment.whenTrue],
      [resourceEnv.whenFalse, environment.whenFalse],
    ]) {
      if (resEnv === null || ghEnv === null) continue;
      const got = roleEnvToSub.get(resEnv);
      if (got === undefined) {
        errors.push(
          `release-web.yml deploys to the "${resEnv}" resources but no deploy role carries that ` +
            'Environment tag.',
        );
      } else if (got !== ghEnv) {
        errors.push(
          `the "${resEnv}" deploy role trusts GitHub environment "${got}", but a run that targets ` +
            `the "${resEnv}" resources declares environment "${ghEnv}". A run in one environment ` +
            "would be assuming the other environment's role.",
        );
      } else {
        ok.push(`GitHub environment "${ghEnv}" ↔ ${resEnv} deploy role`);
      }
    }
  }

  // ── 4. + 5. inline policies: no wildcards, one environment each ──
  /** @type {Set<string>} */
  const usedExemptions = new Set();
  const byRole = new Map(oidc.policies.map((p) => [p.roleLabel, p]));

  for (const role of oidc.roles) {
    const policy = byRole.get(role.label);
    if (policy === undefined || policy.statements.length === 0) {
      errors.push(
        `aws_iam_role.${role.label} has no readable inline aws_iam_role_policy — its grants were ` +
          'not checked.',
      );
      continue;
    }
    for (const st of policy.statements) {
      const at = `aws_iam_role.${role.label} statement ${JSON.stringify(st.sid)}`;
      if (st.actions.length === 0) {
        errors.push(`${at}: no Action list could be read.`);
        continue;
      }
      for (const action of st.actions) {
        if (action === '*' || action.endsWith(':*')) {
          errors.push(
            `${at}: grants ${JSON.stringify(action)}. A service-wide action grant is never what a ` +
              'deploy pipeline needs — enumerate the calls the workflow actually makes.',
          );
        }
      }
      if (st.resources.includes('*')) {
        for (const action of st.actions) {
          const reason = RESOURCELESS_ACTIONS.get(action);
          if (reason === undefined) {
            errors.push(
              `${at}: grants ${JSON.stringify(action)} on Resource "*". Scope it to an ARN, or add ` +
                'it to RESOURCELESS_ACTIONS in this guard with the reason AWS models no resource for it.',
            );
          } else {
            usedExemptions.add(action);
          }
        }
      }
      for (const resource of st.resources) {
        if (resource === '*') continue;
        const fields = resource.split(':');
        if (fields[3] === '*' || fields[4] === '*') {
          errors.push(
            `${at}: resource ${JSON.stringify(resource)} wildcards its region or account field.`,
          );
        }
        if (role.envToken === null) continue;
        if (!resource.includes(`-${role.envToken}-`)) {
          errors.push(
            `${at}: resource ${JSON.stringify(resource)} carries no -${role.envToken}- token, so ` +
              "this role's reach cannot be confirmed to stop at its own environment.",
          );
        }
        for (const other of envTokens) {
          if (other === role.envToken) continue;
          if (resource.includes(`-${other}-`)) {
            errors.push(
              `${at}: the ${role.envToken} role can reach ${JSON.stringify(resource)}, which belongs ` +
                `to ${other}. This is the copy-paste that hands a ${role.envToken} deploy write ` +
                `access to ${other}.`,
            );
          }
        }
      }
    }
  }

  for (const [action, reason] of RESOURCELESS_ACTIONS) {
    if (!usedExemptions.has(action)) {
      errors.push(
        `RESOURCELESS_ACTIONS exempts ${JSON.stringify(action)} ("${reason}") but no statement ` +
          'grants it on "*" any more. Drop the entry — a stale exemption reads as a decision ' +
          'someone made about a grant that is gone.',
      );
    }
  }

  // ── 6. the deploy policies' Lambda list vs the module's functions ──
  if (web.prefix === null || !web.prefix.includes('${var.env}')) {
    errors.push(
      'could not read `local.resource_prefix` from the web-stack module, so the deploy policies\' ' +
        'Lambda ARNs were not compared with the functions they are meant to cover.',
    );
  } else if (web.functions.size === 0) {
    errors.push(
      'no aws_lambda_function with an interpolated name was read from the web-stack module — the ' +
        'Lambda coverage check would pass vacuously.',
    );
  } else {
    const head = web.prefix.slice(0, web.prefix.indexOf('${var.env}'));
    const suffixes = new Set(web.functions.values());
    for (const role of oidc.roles) {
      const policy = byRole.get(role.label);
      if (policy === undefined || role.envToken === null) continue;
      /** @type {Set<string>} */
      const granted = new Set();
      for (const st of policy.statements) {
        for (const resource of st.resources) {
          const fn = resource.match(/:function:(.+)$/)?.[1];
          if (fn === undefined) continue;
          const bare = fn.endsWith('*') ? fn.slice(0, -1) : fn;
          const expectedHead = `${head}${role.envToken}-`;
          if (!bare.startsWith(expectedHead)) {
            errors.push(
              `aws_iam_role.${role.label}: Lambda resource ${JSON.stringify(resource)} does not name a ` +
                `${expectedHead}* function.`,
            );
            continue;
          }
          granted.add(bare.slice(expectedHead.length));
        }
      }
      const uncovered = [...suffixes].filter((s) => !granted.has(s));
      const unknown = [...granted].filter((s) => !suffixes.has(s));
      if (uncovered.length > 0) {
        errors.push(
          `aws_iam_role.${role.label}: the module declares Lambda(s) ${JSON.stringify(uncovered)} that ` +
            'this deploy policy does not grant. The release workflow updates every function, so the ' +
            'run fails at `aws lambda update-function-code` with AccessDenied — mid-deploy, after the ' +
            'S3 sync has already landed.',
        );
      }
      if (unknown.length > 0) {
        errors.push(
          `aws_iam_role.${role.label}: the deploy policy grants Lambda(s) ${JSON.stringify(unknown)} ` +
            'that the module does not declare. Either a function was renamed and the grant left behind, ' +
            'or the policy reaches something Terraform does not own.',
        );
      }
      if (uncovered.length === 0 && unknown.length === 0) {
        ok.push(
          `aws_iam_role.${role.label}: grants exactly the ${suffixes.size} module Lambda(s)`,
        );
      }
    }
  }

  // ── 7. every Function URL is AWS_IAM and carries both CloudFront grants ──
  if (web.urls.size === 0) {
    errors.push(
      'no aws_lambda_function_url was read from the web-stack module — the origin-reachability ' +
        'check would pass vacuously.',
    );
  }
  // A block whose `function_name` is not written as `aws_lambda_function.<label>.`
  // is skipped by the parser above, and a skipped Function URL is one whose
  // authorization_type nothing reads. That is silent: the loop below simply has
  // one fewer thing to iterate, which looks exactly like a stack with one fewer
  // Lambda.
  if (web.declared.urls !== web.urls.size) {
    errors.push(
      `${web.declared.urls} aws_lambda_function_url block(s) in the module, ${web.urls.size} read. ` +
        'A block naming its function some other way is skipped, and a skipped Function URL is one ' +
        'whose auth type and CloudFront grants are checked by nothing.',
    );
  }
  const unattributed = web.permissions.filter((p) => p.fn === null).length;
  if (unattributed > 0) {
    errors.push(
      `${unattributed} aws_lambda_permission block(s) name no aws_lambda_function, so they belong to ` +
        'no function below and every grant they carry went unread.',
    );
  }
  for (const [fn, url] of web.urls) {
    const authType = url.authType;
    // The Function URL is created ON THE ALIAS, so the URL invokes the alias
    // ARN. A resource-policy statement carrying no qualifier is attached to the
    // UNQUALIFIED function and does not authorise that invocation: the URL 403s
    // before invocation and the distribution's SPA error fallback rewrites the
    // 403 into the shell at 200 — the same invisible outage issue #590
    // measured, one field over.
    if (url.qualifier !== null) {
      const aliasLabel = url.qualifier.match(/^aws_lambda_alias\.([A-Za-z0-9_-]+)\.name$/)?.[1];
      const alias = aliasLabel === undefined ? undefined : web.aliases.get(aliasLabel);
      if (alias === undefined) {
        errors.push(
          `aws_lambda_function_url for ${fn}: qualifier ${JSON.stringify(url.qualifier)} does not ` +
            'name an aws_lambda_alias this module declares, so which version the URL serves could ' +
            'not be read.',
        );
      } else if (alias.fn !== fn) {
        errors.push(
          `aws_lambda_function_url for ${fn}: qualified by aws_lambda_alias.${alias.label}, which is ` +
            `an alias of ${alias.fn}. Every alias here is named "live", so this applies cleanly and ` +
            'serves the wrong function rather than failing.',
        );
      }
    }
    const grants = web.permissions.filter((p) => p.fn === fn);
    for (const action of ['lambda:InvokeFunctionUrl', 'lambda:InvokeFunction']) {
      const grant = grants.find((g) => g.action === action);
      if (grant !== undefined && grant.qualifier !== url.qualifier) {
        errors.push(
          `${fn}: the Function URL is qualified by ${JSON.stringify(url.qualifier)} but its ${action} ` +
            `grant by ${JSON.stringify(grant.qualifier)}. A Lambda resource policy is attached per ` +
            'qualifier, so the grant does not cover the ARN CloudFront actually invokes: the URL ' +
            "403s before invocation and the distribution's SPA fallback rewrites that into the shell " +
            'at 200, so the surface reads healthy while the function never runs (issue #590).',
        );
      }
    }
    if (authType !== 'AWS_IAM') {
      errors.push(
        `aws_lambda_function_url for ${fn}: authorization_type is ${JSON.stringify(authType)}. ` +
          'Anything but AWS_IAM makes the .lambda-url hostname world-invocable, bypassing CloudFront, ' +
          'its WAF rate limits and its response-headers policy.',
      );
    }
    for (const action of ['lambda:InvokeFunctionUrl', 'lambda:InvokeFunction']) {
      const grant = grants.find((g) => g.action === action);
      if (grant === undefined) {
        errors.push(
          `${fn}: no aws_lambda_permission grants ${action} to CloudFront. AWS's OAC-for-Lambda ` +
            'contract needs BOTH grants; with one, the Function URL 403s before invocation and the ' +
            "distribution's SPA error fallback rewrites that 403 into the shell at 200 — the surface " +
            'reads healthy while the function never runs (issue #590).',
        );
        continue;
      }
      if (grant.principal !== 'cloudfront.amazonaws.com') {
        errors.push(
          `${fn}: the ${action} grant names principal ${JSON.stringify(grant.principal)} rather than ` +
            'cloudfront.amazonaws.com.',
        );
      }
      if (grant.sourceArn !== 'aws_cloudfront_distribution.this.arn') {
        errors.push(
          `${fn}: the ${action} grant's source_arn is ${JSON.stringify(grant.sourceArn)} rather than ` +
            "this env's own distribution — without it any CloudFront distribution in any account can " +
            'invoke the function.',
        );
      }
    }
    if (grants.length >= 2) {
      ok.push(`${fn}: AWS_IAM Function URL with both CloudFront invoke grants`);
    }
  }

  // ── 8. no Lambda environment takes the secrets file whole ──
  if (web.secretMerges.length === 0) {
    errors.push(
      'no `*_lambda_env` local was read reaching into data.sops_file — either no Lambda takes a ' +
        'secret any more, or this reader stopped matching and a whole-file merge would go unseen.',
    );
  }
  for (const merge of web.secretMerges) {
    if (merge.filter === null) {
      errors.push(
        `local.${merge.local} merges the decrypted sops map whole. Every key the file grows for any ` +
          "OTHER consumer then lands in that function's environment whether its handler reads it or " +
          'not — readable by anyone who can call GetFunctionConfiguration, and by any code-execution ' +
          'bug in the handler. Take the keys by name, the way the generate-route env does.',
      );
    } else {
      ok.push(`local.${merge.local}: sops keys filtered by \`${merge.filter}\``);
    }
  }

  return { errors, ok };
}

export function main() {
  const moduleSrc = readFileSync(MODULE_FILE, 'utf-8');
  const { errors, ok } = compareSources(
    parseOidcStack(readFileSync(OIDC_FILE, 'utf-8')),
    parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8')),
    parseWebStack(moduleSrc),
    readFileSync(OIDC_VARS_FILE, 'utf-8'),
  );

  const grant = checkDecryptGrant(
    parseKmsDecryptGrant(moduleSrc),
    ENV_FILES.map((path) => ({
      path,
      ...parseEnvWire(readFileSync(path, 'utf-8')),
    })),
    parseWorkflowJobs(readWorkflowFiles(WORKFLOW_DIR)),
    credentialedActions(ACTION_DIR),
  );
  errors.push(...grant.errors);
  ok.push(...grant.ok);

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(
      `\n${errors.length} IAM finding(s) under infra/.\n` +
        `  oidc:      ${OIDC_FILE}\n` +
        `  module:    ${MODULE_FILE}\n` +
        `  release:   ${RELEASE_FILE}\n` +
        `  envs:      ${ENV_FILES.join(', ')}\n` +
        `  workflows: ${WORKFLOW_DIR}\n`,
    );
    return 1;
  }
  console.log(`\n${ok.length} IAM property/properties hold across infra/.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
