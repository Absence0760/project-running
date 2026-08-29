#!/usr/bin/env node
// Turn an Edge Function source module into a neutered twin: every name it
// exported still exports, with the same runtime SHAPE, and none of them does
// anything.
//
// Shape preservation is the whole design constraint, and it points the
// opposite way to intuition. The harness scores a test that still passes as
// vacuous, so anything that makes a test fail for an incidental reason - an
// `await` on a non-thenable, an `instanceof` against a stubbed-away class -
// hides a vacuous test behind a kill it did not earn. An async function stays
// async, a class stays a class, and a function stays callable with any arity.
// Only the ANSWER is taken away.
//
// Names are read with a scanner rather than a regex because a `}` inside a
// regex literal or a template literal moves the brace depth, and depth is what
// separates a top-level `export` from one nested in a block. `_shared/
// input_validation.ts` opens with a timestamptz regex full of braces.

/** @typedef {'function' | 'async function' | 'class' | 'value' | 'type' | 'default'} ExportKind */
/** @typedef {{ kind: ExportKind, name: string }} ExportedName */

const IDENT = /[A-Za-z_$][A-Za-z0-9_$]*/y;

// A `/` opens a regex literal only where a value cannot precede it. The last
// significant character is enough to decide for this tree: after an
// identifier, a literal, or a closing bracket it is division.
const DIV_BEFORE = /[A-Za-z0-9_$)\]]/;

/**
 * Every top-level `export` in a TypeScript module, with the kind that decides
 * how its stub must be shaped.
 * @param {string} src
 * @returns {ExportedName[]}
 */
export function topLevelExports(src) {
  /** @type {ExportedName[]} */
  const out = [];
  let depth = 0;
  let lastSignificant = '';
  const n = src.length;
  for (let i = 0; i < n; i++) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') {
      i = src.indexOf('\n', i);
      if (i === -1) break;
      continue;
    }
    if (c === '/' && src[i + 1] === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? n : end + 1;
      continue;
    }
    if (c === '"' || c === "'") {
      i = skipQuoted(src, i, c);
      lastSignificant = c;
      continue;
    }
    if (c === '`') {
      i = skipTemplate(src, i);
      lastSignificant = '`';
      continue;
    }
    if (c === '/' && !DIV_BEFORE.test(lastSignificant)) {
      const end = skipRegex(src, i);
      if (end !== null) {
        i = end;
        lastSignificant = '/';
        continue;
      }
    }
    if (c === '{' || c === '(' || c === '[') depth++;
    else if (c === '}' || c === ')' || c === ']') depth--;
    if (/\s/.test(c)) continue;

    if (
      depth === 0 &&
      c === 'e' &&
      src.startsWith('export', i) &&
      !/[A-Za-z0-9_$]/.test(src[i + 6] ?? '') &&
      !/[A-Za-z0-9_$.]/.test(lastSignificant)
    ) {
      const parsed = parseExportHead(src, i + 6);
      out.push(...parsed.names);
      lastSignificant = 'export';
      // Deliberately do NOT skip the declaration: its body still has to be
      // scanned so its braces keep the depth honest.
      continue;
    }
    lastSignificant = c;
  }
  return dedupe(out);
}

/**
 * @param {ExportedName[]} names
 * @returns {ExportedName[]}
 */
function dedupe(names) {
  /** @type {Map<string, ExportedName>} */
  const byName = new Map();
  for (const entry of names) {
    const seen = byName.get(entry.name);
    // A name exported as both a type and a value must be stubbed as the
    // value, or the runtime binding disappears.
    if (!seen || (seen.kind === 'type' && entry.kind !== 'type')) {
      byName.set(entry.name, entry);
    }
  }
  return [...byName.values()];
}

/**
 * @param {string} src
 * @param {number} at index just past the `export` keyword
 * @returns {{ names: ExportedName[] }}
 */
function parseExportHead(src, at) {
  let i = skipSpace(src, at);
  if (src.startsWith('default', i)) return { names: [{ kind: 'default', name: 'default' }] };

  let typeOnly = false;
  if (word(src, i) === 'type') {
    // `export type {A, B}` is a type-only re-export; `export type X = …` is a
    // type alias. Both erase, but the first still has to be enumerated.
    const after = skipSpace(src, i + 4);
    if (src[after] === '{') {
      typeOnly = true;
      i = after;
    } else {
      return { names: [{ kind: 'type', name: readIdent(src, after) }] };
    }
  }

  if (src[i] === '{') {
    const close = src.indexOf('}', i);
    const body = src.slice(i + 1, close === -1 ? src.length : close);
    /** @type {ExportedName[]} */
    const names = [];
    for (const part of body.split(',')) {
      const trimmed = part.trim();
      if (!trimmed) continue;
      const asIdx = trimmed.search(/\bas\b/);
      const raw = asIdx === -1 ? trimmed : trimmed.slice(asIdx + 2);
      const local = raw.trim().replace(/^type\s+/, '');
      if (local) names.push({ kind: typeOnly ? 'type' : 'value', name: local });
    }
    return { names };
  }

  let kw = word(src, i);
  let isAsync = false;
  if (kw === 'async') {
    isAsync = true;
    i = skipSpace(src, i + 5);
    kw = word(src, i);
  }
  const after = skipSpace(src, i + kw.length);
  if (kw === 'function') {
    const nameAt = src[after] === '*' ? skipSpace(src, after + 1) : after;
    return { names: [{ kind: isAsync ? 'async function' : 'function', name: readIdent(src, nameAt) }] };
  }
  if (kw === 'class') return { names: [{ kind: 'class', name: readIdent(src, after) }] };
  if (kw === 'interface') return { names: [{ kind: 'type', name: readIdent(src, after) }] };
  if (kw === 'const' || kw === 'let' || kw === 'var') {
    return { names: [{ kind: 'value', name: readIdent(src, after) }] };
  }
  return { names: [] };
}

/**
 * @param {string} src
 * @param {number} i
 * @returns {number}
 */
function skipSpace(src, i) {
  while (i < src.length && /\s/.test(src[i])) i++;
  return i;
}

/**
 * @param {string} src
 * @param {number} i
 * @returns {string}
 */
function word(src, i) {
  IDENT.lastIndex = i;
  return IDENT.exec(src)?.[0] ?? '';
}

/**
 * @param {string} src
 * @param {number} i
 * @returns {string}
 */
function readIdent(src, i) {
  return word(src, skipSpace(src, i));
}

/**
 * @param {string} src
 * @param {number} i index of the opening quote
 * @param {string} q
 * @returns {number} index of the closing quote
 */
function skipQuoted(src, i, q) {
  for (let j = i + 1; j < src.length; j++) {
    if (src[j] === '\\') {
      j++;
      continue;
    }
    if (src[j] === q) return j;
    if (src[j] === '\n') return j - 1;
  }
  return src.length;
}

/**
 * @param {string} src
 * @param {number} i index of the opening backtick
 * @returns {number} index of the closing backtick
 */
function skipTemplate(src, i) {
  for (let j = i + 1; j < src.length; j++) {
    if (src[j] === '\\') {
      j++;
      continue;
    }
    if (src[j] === '`') return j;
    if (src[j] === '$' && src[j + 1] === '{') {
      let depth = 1;
      j += 2;
      for (; j < src.length && depth > 0; j++) {
        if (src[j] === '{') depth++;
        else if (src[j] === '}') depth--;
        else if (src[j] === '`') j = skipTemplate(src, j);
        else if (src[j] === '"' || src[j] === "'") j = skipQuoted(src, j, src[j]);
      }
      j--;
    }
  }
  return src.length;
}

/**
 * @param {string} src
 * @param {number} i index of the opening slash
 * @returns {number | null} index of the closing slash, or null if this `/` is not a regex
 */
function skipRegex(src, i) {
  let inClass = false;
  for (let j = i + 1; j < src.length; j++) {
    const c = src[j];
    if (c === '\\') {
      j++;
      continue;
    }
    if (c === '\n') return null;
    if (c === '[') inClass = true;
    else if (c === ']') inClass = false;
    else if (c === '/' && !inClass) return j;
  }
  return null;
}

/**
 * The neutered twin of a module: same exported names, same runtime shapes, no
 * behaviour and no source text for a wiring guard to read.
 * @param {string} src
 * @param {string} rel path, for the marker comment
 * @returns {string}
 */
export function neuterModule(src, rel) {
  const lines = [`// neutered by edge_function_neuter.mjs: ${rel}`];
  for (const { kind, name } of topLevelExports(src)) {
    if (kind === 'default') lines.push('export default undefined;');
    else if (kind === 'function') lines.push(`export function ${name}() { return undefined; }`);
    else if (kind === 'async function') {
      lines.push(`export async function ${name}() { return undefined; }`);
    } else if (kind === 'class') lines.push(`export class ${name} extends Error {}`);
    else lines.push(`export const ${name} = undefined;`);
  }
  return lines.join('\n') + '\n';
}
