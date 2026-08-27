#!/usr/bin/env node
// Guardrail: verify `bin/lambda-alias-sync.sh` repoints every Lambda alias
// Terraform actually declares, by reading both sources and comparing them.
//
// Why this exists: decisions.md § 433. An env-only `terraform apply` publishes
// a fresh Lambda version but the `live` aliases are CI-owned
// (`ignore_changes = [function_version]`), so the rotation never reaches the
// Function URL's serving qualifier — issue #590 defect 2, a disabled API key
// served for as long as nobody noticed. The remedy is the sync script, whose
// coverage was a hand-maintained bash array: correct for the eight Lambdas
// that existed, and silently short by one the day a ninth is added. A Lambda
// missing from that array gets no alias repoint, which is the exact drift
// class § 433 was opened over, reintroduced one function at a time.
//
// Terraform is the source of truth for which Lambdas exist and which of them
// carry a `live` alias. Nothing here transcribes the function list — a
// transcription snapshot is what § 416/§ 439 replaced for the GATT UUIDs, and
// it fails the same way: it agrees with the source right up until the source
// moves. Every name below is read from a file.
//
// `.github/workflows/release-web.yml` is read as a third source because the
// script's own header claims lockstep with it, and a Lambda the release
// workflow does not deploy never gets code at all — the same defect one step
// earlier. Enforcing half of a stated lockstep leaves the other half latent.
//
// Offline by design: three files, no AWS credentials, no `terraform init`.
//
// Run: `node scripts/check_lambda_alias_sync.mjs`
// CI:  the `lambda-alias-coverage` job in .github/workflows/ci.yml, which is
//      in the `CI gate` aggregator's `needs:` list — a guard nothing runs
//      enforces nothing (§ 439).
// Unit tests: `node --test scripts/check_lambda_alias_sync.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at
// mutated copies of the three files, which is how a guard is shown to fail.
export const TERRAFORM_FILE =
  process.env.LAMBDA_ALIAS_TF ??
  join(REPO_ROOT, 'infra/modules/web-stack/main.tf');
export const SCRIPT_FILE =
  process.env.LAMBDA_ALIAS_SH ?? join(REPO_ROOT, 'bin/lambda-alias-sync.sh');
export const RELEASE_FILE =
  process.env.LAMBDA_ALIAS_RELEASE ??
  join(REPO_ROOT, '.github/workflows/release-web.yml');

// Each source spells the environment differently — `${var.env}` in HCL,
// `${ENV_NAME}` in the script, `${ENV}` in the workflow — so each parser
// normalises its own to this sentinel. Comparing the resulting names then
// compares the NAMES rather than the per-language syntax wrapped around them,
// and a prefix that drifts in one source alone still shows up as a mismatch.
export const ENV = '<env>';

/**
 * @typedef {{ label: string, body: string }} HclResource
 * @typedef {{ label: string, aliasName: string | null, functionLabel: string | null, functionName: string | null }} TerraformAlias
 * @typedef {{ resourcePrefix: string | null, functions: Map<string, string>, aliases: TerraformAlias[] }} TerraformModule
 * @typedef {{ functions: string[], loopVar: string | null, template: string | null, prefix: string | null, templateVar: string | null, aliasNames: Set<string> }} SyncScript
 * @typedef {{ outputKey: string | null, aliasName: string | null, functionName: string | null }} ReleaseEntry
 * @typedef {{ outputs: Map<string, string>, entries: ReleaseEntry[] }} ReleaseWorkflow
 */

// ─────────────────────────── HCL block reader ───────────────────────────

// Index of the byte just past the block that opens at `open`, or -1. Braces
// inside strings and comments do not count, which is what keeps a
// `"${local.resource_prefix}-coach"` interpolation from unbalancing the scan.
/**
 * @param {string} src
 * @param {number} open
 * @returns {number}
 */
function blockEnd(src, open) {
  let depth = 0;
  let inString = false;
  let inLine = false;
  let inBlock = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    const n = src[i + 1];
    if (inLine) {
      if (c === '\n') inLine = false;
      continue;
    }
    if (inBlock) {
      if (c === '*' && n === '/') {
        inBlock = false;
        i++;
      }
      continue;
    }
    if (inString) {
      if (c === '\\') i++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === '#') inLine = true;
    else if (c === '/' && n === '/') {
      inLine = true;
      i++;
    } else if (c === '/' && n === '*') {
      inBlock = true;
      i++;
    } else if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/**
 * Every `resource "<type>" "<label>" { … }` of one type, as {label, body}.
 *
 * @param {string} src
 * @param {string} type
 * @returns {HclResource[]}
 */
export function hclResources(src, type) {
  const re = new RegExp(
    `(?:^|\\n)\\s*resource\\s+"${type}"\\s+"([A-Za-z0-9_-]+)"\\s*\\{`,
    'g',
  );
  /** @type {HclResource[]} */
  const out = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = blockEnd(src, open);
    if (close < 0) continue;
    out.push({ label: m[1], body: src.slice(open + 1, close) });
  }
  return out;
}

// ─────────────────────────────── parsers ────────────────────────────────

// The module's `local.resource_prefix`, every `aws_lambda_function`'s name,
// and every `aws_lambda_alias` resolved through to the function name it
// targets. An alias whose `function_name` is not a plain reference resolves
// to null rather than being guessed at — see compareSources.
/**
 * @param {string} src
 * @returns {TerraformModule}
 */
export function parseTerraform(src) {
  const prefixLine = src.match(/^[ \t]*resource_prefix\s*=\s*"([^"]*)"/m);
  const resourcePrefix = prefixLine
    ? prefixLine[1].replaceAll('${var.env}', ENV)
    : null;

  /** @type {Map<string, string>} */
  const functions = new Map();
  for (const { label, body } of hclResources(src, 'aws_lambda_function')) {
    const nm = body.match(/^[ \t]*function_name\s*=\s*"([^"]*)"/m);
    if (!nm) continue;
    let name = nm[1].replaceAll('${var.env}', ENV);
    if (resourcePrefix !== null) {
      name = name.replaceAll('${local.resource_prefix}', resourcePrefix);
    }
    functions.set(label, name);
  }

  /** @type {TerraformAlias[]} */
  const aliases = [];
  for (const { label, body } of hclResources(src, 'aws_lambda_alias')) {
    const aliasName = body.match(/^[ \t]*name\s*=\s*"([^"]*)"/m)?.[1] ?? null;
    const ref =
      body.match(
        /^[ \t]*function_name\s*=\s*aws_lambda_function\.([A-Za-z0-9_-]+)\.function_name/m,
      )?.[1] ?? null;
    aliases.push({
      label,
      aliasName,
      functionLabel: ref,
      functionName: ref === null ? null : (functions.get(ref) ?? null),
    });
  }

  return { resourcePrefix, functions, aliases };
}

// `FUNCTIONS=(…)`, the `NAME="…"` template the loop builds each function name
// from, and the alias name the aws calls ask for. The loop variable is read
// too: a loop that stopped iterating FUNCTIONS would leave the array parsed
// and meaningless, so the two are checked against each other.
/**
 * @param {string} src
 * @returns {SyncScript}
 */
export function parseSyncScript(src) {
  const arr = src.match(/^[ \t]*FUNCTIONS=\(([^)]*)\)/m);
  const functions = arr
    ? arr[1]
        .split(/\s+/)
        .filter(Boolean)
        .map((s) => s.replace(/^['"]|['"]$/g, ''))
    : [];

  const loopVar =
    src.match(
      /\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+"\$\{FUNCTIONS\[@\]\}"/,
    )?.[1] ?? null;

  const tmpl = src.match(/^[ \t]*NAME=\s*"([^"]*)"/m)?.[1] ?? null;
  /** @type {string | null} */
  let prefix = null;
  /** @type {string | null} */
  let templateVar = null;
  if (tmpl !== null) {
    const t = tmpl.replaceAll('${ENV_NAME}', ENV);
    const m = t.match(/^(.*)-\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/);
    if (m) {
      prefix = m[1];
      templateVar = m[2];
    }
  }

  /** @type {Set<string>} */
  const aliasNames = new Set();
  // `\s` and not `(?:^|\s)`: the pattern requires `aws lambda …-alias`
  // before this point, so a `^` without the `m` flag could only ever match at
  // offset 0 and never here — a dead alternative, which is precisely the
  // silently-stops-matching failure this whole guard exists to prevent.
  // A newline is whitespace, so `\s` already covers the start-of-line case.
  const re = /aws\s+lambda\s+(?:get|update)-alias\b[\s\S]{0,400}?\s--name\s+(\S+)/g;
  let m;
  while ((m = re.exec(src)) !== null) aliasNames.add(m[1]);

  return { functions, loopVar, template: tmpl, prefix, templateVar, aliasNames };
}

// The release workflow's per-function deploy steps. Each `aws lambda
// update-alias` is read for the `--function-name` it targets and the `--name`
// it repoints, then the `steps.aws.outputs.<key>` reference is resolved back
// through the `echo "<key>=…" >> "$GITHUB_OUTPUT"` line that defines it — so
// the function names come out of the workflow rather than out of a list here.
/**
 * @param {string} src
 * @returns {ReleaseWorkflow}
 */
export function parseReleaseWorkflow(src) {
  /** @type {Map<string, string>} */
  const outputs = new Map();
  const outRe =
    /echo\s+"([A-Za-z_][A-Za-z0-9_]*)=([^"]*)"\s*>>\s*"\$GITHUB_OUTPUT"/g;
  let o;
  while ((o = outRe.exec(src)) !== null) {
    outputs.set(o[1], o[2].replaceAll('${ENV}', ENV));
  }

  /** @type {ReleaseEntry[]} */
  const entries = [];
  const callRe = /aws lambda update-alias\b((?:[^\n]*\\\n)*[^\n]*)/g;
  let m;
  while ((m = callRe.exec(src)) !== null) {
    const args = m[1];
    const fnArg = args.match(/--function-name\s+"([^"]*)"/)?.[1] ?? null;
    const aliasName = args.match(/(?:^|\s)--name\s+(\S+)/)?.[1] ?? null;
    const ref =
      fnArg === null
        ? null
        : (fnArg.match(
            /\$\{\{\s*steps\.aws\.outputs\.([A-Za-z0-9_]+)\s*\}\}/,
          )?.[1] ?? null);
    entries.push({
      outputKey: ref,
      aliasName,
      functionName: ref === null ? null : (outputs.get(ref) ?? null),
    });
  }

  return { outputs, entries };
}

// A full name split at the env sentinel: `threkir-web-<env>-coach` becomes
// prefix `threkir-web-<env>` and suffix `coach`. Null when the name carries no
// env at all, which would mean an environment-invariant Lambda name — the
// script could not address it per-env, so that has to be loud.
/**
 * @param {string} full
 * @returns {{ prefix: string, suffix: string } | null}
 */
export function splitName(full) {
  const i = full.indexOf(ENV);
  if (i < 0) return null;
  const rest = full.slice(i + ENV.length);
  if (!rest.startsWith('-') || rest.length < 2) return null;
  return { prefix: full.slice(0, i + ENV.length), suffix: rest.slice(1) };
}

// ────────────────────────────── comparison ──────────────────────────────

// The whole verdict as data, so the tests can assert on it without capturing
// stdout. `errors` fails the build; `warnings` do not.
/**
 * @param {TerraformModule} tf
 * @param {SyncScript} sh
 * @param {ReleaseWorkflow} rel
 * @returns {{ errors: string[], warnings: string[], ok: string[] }}
 */
export function compareSources(tf, sh, rel) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const warnings = [];
  /** @type {string[]} */
  const ok = [];

  // Vacuity guards. A parser that quietly stops matching would otherwise
  // compare two empty sets and report agreement — the failure mode that makes
  // a source-parsing guard worse than no guard, because the repo believes
  // itself defended.
  if (tf.aliases.length === 0) {
    errors.push(
      'Parsed no aws_lambda_alias resources out of the Terraform module.\n' +
        '  The declaration moved or changed shape; this guard is blind until ' +
        'parseTerraform() is taught the new form.',
    );
  }
  if (sh.functions.length === 0) {
    errors.push(
      'Parsed no FUNCTIONS entries out of bin/lambda-alias-sync.sh.\n' +
        '  The array moved or changed shape; this guard is blind until ' +
        'parseSyncScript() is taught the new form.',
    );
  }
  if (rel.entries.length === 0) {
    errors.push(
      'Parsed no `aws lambda update-alias` steps out of release-web.yml.\n' +
        '  The deploy steps moved or changed shape; this guard is blind until ' +
        'parseReleaseWorkflow() is taught the new form.',
    );
  }

  // The script's own internals have to hold up before its list means anything.
  if (sh.loopVar === null) {
    errors.push(
      'bin/lambda-alias-sync.sh no longer loops over "${FUNCTIONS[@]}".\n' +
        '  Whatever it iterates now is what this guard must compare against.',
    );
  }
  if (sh.prefix === null) {
    errors.push(
      'Could not read the per-function name template (NAME="…") out of ' +
        'bin/lambda-alias-sync.sh.\n' +
        '  Expected a `<prefix>-${<var>}` shape ending in the loop variable.',
    );
  } else if (sh.loopVar !== null && sh.templateVar !== sh.loopVar) {
    errors.push(
      `bin/lambda-alias-sync.sh builds its function name from \${${sh.templateVar}} ` +
        `but loops over \${${sh.loopVar}}.\n` +
        '  One of the two is wrong; the script would address the same name every ' +
        'iteration.',
    );
  }
  if (sh.functions.length > 0 && sh.aliasNames.size === 0) {
    errors.push(
      'bin/lambda-alias-sync.sh names no alias in its `aws lambda …-alias` ' +
        'calls.\n' +
        '  Repointing a named alias is the whole job; with none read here the ' +
        'comparison below runs on the other two sources alone.',
    );
  }
  if (tf.resourcePrefix === null) {
    errors.push(
      'Could not read `local.resource_prefix` out of the Terraform module.\n' +
        '  Every Lambda name is derived from it, so this guard cannot resolve ' +
        'any of them.',
    );
  }

  // Terraform → the set of (suffix, alias name) pairs it actually declares.
  /** @type {Map<string, TerraformAlias>} */
  const tfSuffixes = new Map();
  /** @type {Set<string>} */
  const tfPrefixes = new Set();
  for (const a of tf.aliases) {
    // An unreadable name drops this alias out of the agreement set below
    // rather than disagreeing with anything, so the two derived sources are
    // left agreeing with each other and the source of truth abstains.
    if (a.aliasName === null) {
      errors.push(
        `aws_lambda_alias."${a.label}" sets no literal \`name = "…"\`.\n` +
          '  Terraform is where the alias name is declared; the other two sources ' +
          'spell it out by hand. With none read here a rename on this side is ' +
          'never noticed.',
      );
    }
    if (a.functionLabel === null) {
      errors.push(
        `aws_lambda_alias."${a.label}" does not set ` +
          '`function_name = aws_lambda_function.<label>.function_name`.\n' +
          '  This guard resolves alias → function → name by that reference and ' +
          'will not guess; give it the reference form or teach parseTerraform() ' +
          'the new one.',
      );
      continue;
    }
    if (a.functionName === null) {
      errors.push(
        `aws_lambda_alias."${a.label}" targets aws_lambda_function."${a.functionLabel}", ` +
          'whose function_name could not be read.\n' +
          '  Either the resource is gone (a dangling reference Terraform would ' +
          'reject) or its name is not a literal string.',
      );
      continue;
    }
    const split = splitName(a.functionName);
    if (split === null) {
      errors.push(
        `aws_lambda_alias."${a.label}" targets "${a.functionName}", which carries ` +
          'no environment component.\n' +
          '  bin/lambda-alias-sync.sh addresses functions per env and could not ' +
          'reach an env-invariant name.',
      );
      continue;
    }
    tfPrefixes.add(split.prefix);
    tfSuffixes.set(split.suffix, a);
  }

  // A Lambda with no alias at all is a warning, not a failure: it is a
  // Terraform-shape question rather than sync-script drift. It is surfaced
  // because in this module a Function URL targets the alias, so a function
  // without one has nothing for CloudFront to invoke.
  const aliased = new Set(
    tf.aliases.map((a) => a.functionLabel).filter((l) => l !== null),
  );
  for (const [label, name] of tf.functions) {
    if (aliased.has(label)) continue;
    warnings.push(
      `aws_lambda_function."${label}" ("${name}") has no aws_lambda_alias.\n` +
        '  Fine if nothing serves through an alias qualifier. If it does, the ' +
        'Function URL has no alias to target and the sync script has nothing to ' +
        'repoint.',
    );
  }

  // release-web.yml → the same shape.
  /** @type {Map<string, ReleaseEntry>} */
  const relSuffixes = new Map();
  /** @type {Set<string>} */
  const relPrefixes = new Set();
  for (const e of rel.entries) {
    if (e.aliasName === null) {
      errors.push(
        'An `aws lambda update-alias` step in release-web.yml passes no ' +
          '`--name`.\n' +
          '  The deploy would fail on a required argument, and this source ' +
          'abstains from the alias-name comparison below.',
      );
    }
    if (e.outputKey === null) {
      errors.push(
        'An `aws lambda update-alias` step in release-web.yml does not name its ' +
          'function via `steps.aws.outputs.<key>`.\n' +
          '  This guard resolves the name through that step output and will not ' +
          'guess.',
      );
      continue;
    }
    if (e.functionName === null) {
      errors.push(
        `release-web.yml repoints \`steps.aws.outputs.${e.outputKey}\`, which the ` +
          '"Resolve target resources" step never sets.\n' +
          '  The deploy would target an empty function name.',
      );
      continue;
    }
    const split = splitName(e.functionName);
    if (split === null) {
      errors.push(
        `release-web.yml repoints "${e.functionName}", which carries no ` +
          'environment component.',
      );
      continue;
    }
    relPrefixes.add(split.prefix);
    relSuffixes.set(split.suffix, e);
  }

  // Prefix agreement. Checked before the set comparison so a renamed prefix
  // reports as one finding rather than as every function missing from both
  // directions at once.
  /** @type {Map<string, string>} */
  const prefixes = new Map();
  for (const p of tfPrefixes) prefixes.set(p, 'Terraform');
  if (sh.prefix !== null && !prefixes.has(sh.prefix)) {
    prefixes.set(sh.prefix, 'bin/lambda-alias-sync.sh');
  }
  for (const p of relPrefixes) {
    if (!prefixes.has(p)) prefixes.set(p, 'release-web.yml');
  }
  if (prefixes.size > 1) {
    errors.push(
      'The three sources do not agree on the Lambda name prefix:\n' +
        [...prefixes].map(([p, who]) => `    ${p} (${who})`).join('\n') +
        '\n  Every function name is prefix + "-" + suffix; a disagreement here ' +
        'means the script addresses functions that do not exist.',
    );
  }

  // Alias-name agreement. The script asks for one alias by name; Terraform
  // declares one per function. A rename on either side is the same silent
  // no-op as a missing list entry.
  const tfAliasNames = new Set(
    tf.aliases.map((a) => a.aliasName).filter((n) => n !== null),
  );
  const relAliasNames = new Set(
    rel.entries.map((e) => e.aliasName).filter((n) => n !== null),
  );
  const allAliasNames = new Set([
    ...tfAliasNames,
    ...sh.aliasNames,
    ...relAliasNames,
  ]);
  if (allAliasNames.size > 1) {
    errors.push(
      'The sources do not agree on the alias name:\n' +
        `    Terraform declares: ${[...tfAliasNames].join(', ') || '(none)'}\n` +
        `    the sync script asks for: ${[...sh.aliasNames].join(', ') || '(none)'}\n` +
        `    release-web.yml repoints: ${[...relAliasNames].join(', ') || '(none)'}\n` +
        '  A repoint of an alias nobody serves through changes nothing.',
    );
  } else if (allAliasNames.size === 0) {
    errors.push(
      'Read no alias name from any of the three sources — this guard is blind ' +
        'to the alias being renamed.',
    );
  }

  // The finding this guard exists for, in both directions.
  for (const [suffix, a] of tfSuffixes) {
    if (sh.functions.includes(suffix)) continue;
    errors.push(
      `Terraform declares aws_lambda_alias."${a.label}" on ` +
        `"${a.functionName}", but bin/lambda-alias-sync.sh never repoints it.\n` +
        `  After an env-only \`terraform apply\` this Lambda keeps serving the ` +
        `previous version's frozen env — issue #590 defect 2, decisions.md § 433.\n` +
        `  Fix: add "${suffix}" to the FUNCTIONS array.`,
    );
  }
  for (const suffix of sh.functions) {
    if (tfSuffixes.has(suffix)) continue;
    errors.push(
      `bin/lambda-alias-sync.sh lists "${suffix}", but Terraform declares no ` +
        'aws_lambda_alias for it.\n' +
        '  A stale entry makes every run report a function that does not exist ' +
        'and hides a real drift in the noise.\n' +
        `  Fix: drop "${suffix}" from the FUNCTIONS array, or add the alias to ` +
        'infra/modules/web-stack/main.tf.',
    );
  }

  for (const [suffix, a] of tfSuffixes) {
    if (relSuffixes.has(suffix)) continue;
    errors.push(
      `Terraform declares aws_lambda_alias."${a.label}" on ` +
        `"${a.functionName}", but release-web.yml never deploys or repoints it.\n` +
        '  A `web@*` release would leave this Lambda on its placeholder bundle.\n' +
        `  Fix: add an "Update ${suffix} Lambda" step and a matching ` +
        '"Resolve target resources" output.',
    );
  }
  for (const [suffix, e] of relSuffixes) {
    if (tfSuffixes.has(suffix)) continue;
    errors.push(
      `release-web.yml repoints "${e.functionName}" (via ` +
        `\`steps.aws.outputs.${e.outputKey}\`), but Terraform declares no ` +
        'aws_lambda_alias for it.\n' +
        '  The deploy step would fail against an alias that was never created.',
    );
  }

  for (const [suffix, a] of tfSuffixes) {
    if (!sh.functions.includes(suffix) || !relSuffixes.has(suffix)) continue;
    ok.push(`${suffix} — aws_lambda_alias."${a.label}", synced and deployed`);
  }

  return { errors, warnings, ok };
}

function main() {
  const { errors, warnings, ok } = compareSources(
    parseTerraform(readFileSync(TERRAFORM_FILE, 'utf-8')),
    parseSyncScript(readFileSync(SCRIPT_FILE, 'utf-8')),
    parseReleaseWorkflow(readFileSync(RELEASE_FILE, 'utf-8')),
  );

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of warnings) console.warn(`[WARN] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(
      `\n${errors.length} disagreement(s) between the Terraform Lambda aliases ` +
        'and the tooling that repoints them.\n' +
        `  terraform: ${TERRAFORM_FILE}\n` +
        `  script:    ${SCRIPT_FILE}\n` +
        `  release:   ${RELEASE_FILE}\n` +
        'Terraform is the source of truth for which Lambdas exist ' +
        '(decisions.md § 433); align the other two to it.',
    );
    return 1;
  }
  console.log(
    `\nTerraform, the sync script and release-web.yml agree on ${ok.length} ` +
      'Lambda alias(es)' +
      (warnings.length ? `, ${warnings.length} warning(s)` : '') +
      '.',
  );
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
