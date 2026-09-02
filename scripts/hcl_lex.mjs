// Brace-accurate reader for Terraform HCL, shared by the guards that read
// `infra/` as text.
//
// Every guard over the Terraform tree needs the same two things: the body of
// one `resource "<type>" "<label>" { … }` block, and the ability to find the
// end of a nested block inside it. A regex cannot do either on this source —
// `"${local.resource_prefix}-coach"` puts a brace inside a string, and several
// comments in the module carry an unbalanced one — so the scan has to know
// about strings and comments. That scanner was written once for
// check_lambda_alias_sync.mjs; a second copy in the next guard is a second
// thing to get wrong, which is why it lives here beside shell_lex.mjs and
// comment_strip.mjs rather than being pasted forward.
//
// Deliberately NOT a general HCL parser. It resolves no expressions, evaluates
// no interpolation and understands no types; callers regex within the body
// they get back, and every one of them declares what it could not read rather
// than guessing.
//
// Unit tests: `node --test scripts/hcl_lex.test.mjs`

/**
 * @typedef {{ label: string, body: string, index: number }} HclResource
 */

/**
 * Index of the closing brace of the block that opens at `open`, or -1 when the
 * source never closes it. Braces inside strings, `#` / `//` line comments and
 * `/* … *\/` block comments do not count toward the depth.
 *
 * @param {string} src
 * @param {number} open index of the opening `{`
 * @returns {number}
 */
export function blockEnd(src, open) {
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
 * Every `resource "<type>" "<label>" { … }` of one type, as `{label, body}`.
 * `index` is the offset of the resource header, so a caller can report where.
 *
 * @param {string} src
 * @param {string} type
 * @returns {HclResource[]}
 */
export function hclResources(src, type) {
  return hclBlocks(src, 'resource', type);
}

/**
 * Every `<keyword> "<type>" "<label>" { … }` block — `resource`, `data`, or
 * anything else spelled with a type and a label.
 *
 * @param {string} src
 * @param {string} keyword
 * @param {string} type
 * @returns {HclResource[]}
 */
export function hclBlocks(src, keyword, type) {
  const re = new RegExp(
    `(?:^|\\n)\\s*${keyword}\\s+"${type}"\\s+"([A-Za-z0-9_-]+)"\\s*\\{`,
    'g',
  );
  /** @type {HclResource[]} */
  const out = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = blockEnd(src, open);
    if (close < 0) continue;
    out.push({ label: m[1], body: src.slice(open + 1, close), index: m.index });
  }
  return out;
}

/**
 * The body of the first nested block whose header matches `header` — e.g.
 * `nested(body, /StringEquals\s*=\s*\{/)`. Null when the header never appears
 * or the block never closes, so a caller can tell "absent" from "empty".
 *
 * @param {string} body
 * @param {RegExp} header must match the header up to and including its `{`
 * @returns {string | null}
 */
export function nestedBlock(body, header) {
  const re = new RegExp(header.source, header.flags.replace('g', ''));
  const m = body.match(re);
  if (!m || m.index === undefined) return null;
  const open = body.indexOf('{', m.index);
  if (open < 0) return null;
  const close = blockEnd(body, open);
  if (close < 0) return null;
  return body.slice(open + 1, close);
}

/**
 * Every nested block whose header matches `header`, in source order — the
 * repeated-block form of `nestedBlock`. A CloudFront distribution declares one
 * `origin` and one `ordered_cache_behavior` block per origin and per route, so
 * reading only the first is reading one of eighteen.
 *
 * The scan resumes past each block's closing brace rather than just past its
 * header, so a header that also occurs INSIDE a block is not returned twice.
 *
 * @param {string} body
 * @param {RegExp} header must match the header up to and including its `{`
 * @returns {HclResource[]} `label` is the matched header text
 */
export function nestedBlocks(body, header) {
  const flags = header.flags.includes('g') ? header.flags : `${header.flags}g`;
  const re = new RegExp(header.source, flags);
  /** @type {HclResource[]} */
  const out = [];
  let m;
  while ((m = re.exec(body)) !== null) {
    const open = body.indexOf('{', m.index);
    if (open < 0) break;
    const close = blockEnd(body, open);
    if (close < 0) break;
    out.push({ label: m[0], body: body.slice(open + 1, close), index: m.index });
    re.lastIndex = close;
  }
  return out;
}

/**
 * `src` with every `#` / `//` line comment and `/* … *\/` block comment
 * replaced by an equal number of spaces and newlines, so offsets and line
 * numbers are preserved. Quoted strings are left intact — a `#` inside one is
 * data, not a comment.
 *
 * Callers that pull quoted values out of a policy document need this: several
 * statements in infra/github-oidc/main.tf carry a prose comment above the
 * `Action` list, and a naive scan for `"…"` reads whatever that prose quotes as
 * one more granted action.
 *
 * @param {string} src
 * @returns {string}
 */
export function stripComments(src) {
  let out = '';
  let inString = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const n = src[i + 1];
    if (inString) {
      out += c;
      if (c === '\\') {
        out += n ?? '';
        i++;
      } else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') {
      inString = true;
      out += c;
      continue;
    }
    if (c === '#' || (c === '/' && n === '/')) {
      while (i < src.length && src[i] !== '\n') {
        out += ' ';
        i++;
      }
      out += '\n';
      continue;
    }
    if (c === '/' && n === '*') {
      const end = src.indexOf('*/', i + 2);
      const stop = end < 0 ? src.length : end + 2;
      for (let j = i; j < stop; j++) out += src[j] === '\n' ? '\n' : ' ';
      i = stop - 1;
      continue;
    }
    out += c;
  }
  return out;
}
