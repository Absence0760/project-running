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
// Offline by design: three files, no AWS credentials, no `terraform init`.
// Nothing here is transcribed — every name, every environment and every
// function suffix is read out of one of the three sources.
//
// Run: `node scripts/check_infra_iam.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list — a guard nothing runs enforces
//      nothing.
// Unit tests: `node --test scripts/check_infra_iam.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { hclResources, nestedBlock, stripComments } from './hcl_lex.mjs';

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
 * @typedef {{ prefix: string | null, functions: Map<string, string>, urls: Map<string, string | null>,
 *             permissions: { fn: string | null, action: string | null, principal: string | null, sourceArn: string | null }[] }} WebStack
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

  /** @type {Map<string, string | null>} */
  const urls = new Map();
  for (const { body } of hclResources(src, 'aws_lambda_function_url')) {
    const fn = body.match(
      /^\s*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\./m,
    )?.[1];
    if (fn === undefined) continue;
    urls.set(
      fn,
      body.match(/^\s*authorization_type\s*=\s*"([^"]*)"/m)?.[1] ?? null,
    );
  }

  /** @type {WebStack['permissions']} */
  const permissions = [];
  for (const { body } of hclResources(src, 'aws_lambda_permission')) {
    permissions.push({
      fn:
        body.match(
          /^\s*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\./m,
        )?.[1] ?? null,
      action: body.match(/^\s*action\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      principal: body.match(/^\s*principal\s*=\s*"([^"]*)"/m)?.[1] ?? null,
      sourceArn: body.match(/^\s*source_arn\s*=\s*(\S+)/m)?.[1] ?? null,
    });
  }

  return { prefix, functions, urls, permissions };
}

// ────────────────────────────── comparison ──────────────────────────────

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
  for (const [fn, authType] of web.urls) {
    if (authType !== 'AWS_IAM') {
      errors.push(
        `aws_lambda_function_url for ${fn}: authorization_type is ${JSON.stringify(authType)}. ` +
          'Anything but AWS_IAM makes the .lambda-url hostname world-invocable, bypassing CloudFront, ' +
          'its WAF rate limits and its response-headers policy.',
      );
    }
    const grants = web.permissions.filter((p) => p.fn === fn);
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

  return { errors, ok };
}

export function main() {
  const { errors, ok } = compareSources(
    parseOidcStack(readFileSync(OIDC_FILE, 'utf-8')),
    parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8')),
    parseWebStack(readFileSync(MODULE_FILE, 'utf-8')),
    readFileSync(OIDC_VARS_FILE, 'utf-8'),
  );

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(
      `\n${errors.length} IAM finding(s) under infra/.\n` +
        `  oidc:    ${OIDC_FILE}\n` +
        `  module:  ${MODULE_FILE}\n` +
        `  release: ${RELEASE_FILE}\n`,
    );
    return 1;
  }
  console.log(`\n${ok.length} IAM property/properties hold across infra/.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
