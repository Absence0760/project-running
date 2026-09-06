// What `docs/features/seo.md`'s render map claims for every surface it calls
// prerendered, read off the BUILT artifact rather than off the source that
// intends it.
//
// The map has claimed "`/` landing | prerendered | SeoHead.svelte + +page.ts |
// Organization + WebSite" for as long as the surface has existed, and for that
// whole time `build/index.html` was adapter-static's SPA fallback: no title, no
// canonical, no description, no JSON-LD. Three rounds diagnosed it, twice
// wrongly, because every source-level reading of the tree agreed with the map --
// `+page.svelte` really does build all of it, `SeoHead` really is mounted, and
// the only place the claim is false is the emitted HTML. So the claim is made
// against the emitted HTML here. decisions § 1268, § 1270.
//
// Needs a build: `npm run build --workspace=apps/web` first, or every case
// self-skips. The self-skip is why this file also runs in the CI job that
// builds (`build-web`), not only in the one that runs the unit suite.
//
// Invocation:
//   npm run build --workspace=apps/web
//   npx tsx --test src/lib/seo/prerendered_head_contract.test.ts

import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { relative, resolve } from "node:path";

const webRoot = resolve(import.meta.dirname, "..", "..", "..");
const BUILD = resolve(webRoot, "build");
const SVELTE_CONFIG = resolve(webRoot, "svelte.config.js");
const SEO_DOC = resolve(webRoot, "..", "..", "docs", "features", "seo.md");
const ROOT_PAGE = resolve(webRoot, "src", "routes", "+page.ts");

const SHELL = (() => {
  const found = /\bfallback:\s*["']([^"']+)["']/.exec(
    readFileSync(SVELTE_CONFIG, "utf8"),
  );
  assert.ok(found, "svelte.config.js sets no adapter fallback");
  return found[1];
})();

function builtPages(): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === "_app") continue;
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (entry.name.endsWith(".html")) out.push(relative(BUILD, full));
    }
  };
  walk(BUILD);
  return out.sort();
}

/// The path a page at this build-relative filename is served at. `index.html`
/// is the site root and keeps its trailing slash; everything else drops the
/// extension. This is the mapping the canonical must agree with, and asserting
/// it is what would have caught the landing page being served as the body of
/// every deep link.
function servedPath(file: string): string {
  return file === "index.html" ? "/" : `/${file.replace(/\.html$/, "")}`;
}

function head(file: string): string {
  const html = readFileSync(resolve(BUILD, file), "utf8");
  const end = html.indexOf("</head>");
  return end === -1 ? html : html.slice(0, end);
}

function skipWithoutBuild(t: { skip: (reason: string) => void }): boolean {
  if (existsSync(BUILD)) return false;
  t.skip(
    "no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact",
  );
  return true;
}

test("the build emits a landing page and a shell, and they are different files", (t) => {
  if (skipWithoutBuild(t)) return;
  assert.ok(
    existsSync(resolve(BUILD, "index.html")),
    "CloudFront serves index.html as default_root_object; without it the site root 403s.",
  );
  assert.ok(
    existsSync(resolve(BUILD, SHELL)),
    `CloudFront rewrites every deep-link 403 to /${SHELL}; without it no client route resolves.`,
  );
  assert.notEqual(
    SHELL,
    "index.html",
    "One file cannot be both: the shell must boot at any URL (absolute asset URLs, no " +
      "route payload) and the landing page must carry a head. decisions § 1268.",
  );
});

test("the built landing page carries every head signal the render map promises", (t) => {
  if (skipWithoutBuild(t)) return;
  const h = head("index.html");

  const titles = [
    ...h.matchAll(/<title[^>]*>([\s\S]*?)<\/title(?=[\s/>])[^>]*>/gi),
  ].map((m) => m[1].trim());
  assert.equal(
    titles.length,
    1,
    `expected exactly one title on /, found ${titles.length}`,
  );
  assert.notEqual(titles[0], "", "/ carries an empty title");
  assert.notEqual(
    titles[0],
    "Threkir",
    "The bare site name is what the SPA shell and the pre-§ 1167 duplicate both presented as.",
  );

  const canonical = /<link rel="canonical" href="([^"]+)"/.exec(h);
  assert.ok(canonical, '/ carries no <link rel="canonical">');
  assert.equal(
    new URL(canonical[1]).pathname,
    "/",
    "the landing page's canonical must name the site root",
  );

  const description = /<meta name="description" content="([^"]*)"/.exec(h);
  assert.ok(description, '/ carries no <meta name="description">');
  assert.notEqual(description[1].trim(), "", "/ carries an empty description");

  for (const property of [
    "og:title",
    "og:description",
    "og:url",
    "og:image",
    "og:type",
  ]) {
    assert.match(
      h,
      new RegExp(`property="${property}"`),
      `/ carries no ${property}`,
    );
  }
  assert.match(h, /name="twitter:card"/, "/ carries no twitter:card");
});

test("the built landing page carries the Organization + WebSite JSON-LD", (t) => {
  if (skipWithoutBuild(t)) return;
  const blocks = [
    ...head("index.html").matchAll(
      /<script type="application\/ld\+json">([\s\S]*?)<\/script(?=[\s/>])[^>]*>/gi,
    ),
  ].map((m) => JSON.parse(m[1]) as { "@type"?: string; "@context"?: string });

  assert.deepEqual(
    blocks.map((b) => b["@type"]).sort(),
    ["Organization", "WebSite"],
    "docs/features/seo.md names both for /; a missing one is a rich result the site " +
      "cannot earn, and an unexpected one is a claim nothing reviewed.",
  );
  for (const block of blocks) {
    assert.equal(
      block["@context"],
      "https://schema.org",
      "a JSON-LD block without the schema.org context is inert",
    );
  }
});

test("every prerendered page carries a canonical naming its own served path", (t) => {
  if (skipWithoutBuild(t)) return;
  const pages = builtPages().filter((f) => f !== SHELL);
  // The population assertion: the landing page, the Learn hub, six category
  // indexes and at least seven guides. A walk that has stopped finding them
  // satisfies every claim below without reading a page.
  assert.ok(
    pages.length >= 15,
    `expected at least 15 prerendered pages, found ${pages.length}: ${pages.join(", ")}`,
  );

  const origins = new Set<string>();
  const wrong: string[] = [];
  for (const file of pages) {
    const canonical = /<link rel="canonical" href="([^"]+)"/.exec(head(file));
    if (!canonical) {
      wrong.push(`${file}: no canonical`);
      continue;
    }
    const url = new URL(canonical[1]);
    origins.add(url.origin);
    if (url.pathname !== servedPath(file)) {
      wrong.push(
        `${file}: canonical ${url.pathname}, served at ${servedPath(file)}`,
      );
    }
  }
  assert.deepEqual(
    wrong,
    [],
    "A canonical naming a path other than the one the file is served at points a crawler " +
      `at a different page, and is how a shell swap goes unnoticed:\n  ${wrong.join("\n  ")}`,
  );
  assert.equal(
    origins.size,
    1,
    `the prerendered surface should advertise one origin, found ${[...origins].join(", ")}`,
  );
});

test("every prerendered page carries a title, a description and social meta", (t) => {
  if (skipWithoutBuild(t)) return;
  const missing: string[] = [];
  for (const file of builtPages().filter((f) => f !== SHELL)) {
    const h = head(file);
    const title = /<title[^>]*>([\s\S]*?)<\/title(?=[\s/>])[^>]*>/i.exec(h);
    if (!title || title[1].trim() === "") missing.push(`${file}: title`);
    const description = /<meta name="description" content="([^"]*)"/.exec(h);
    if (!description || description[1].trim() === "")
      missing.push(`${file}: description`);
    if (!/property="og:title"/.test(h)) missing.push(`${file}: og:title`);
    if (!/property="og:image"/.test(h)) missing.push(`${file}: og:image`);
    if (!/name="twitter:card"/.test(h)) missing.push(`${file}: twitter:card`);
  }
  assert.deepEqual(
    missing,
    [],
    "These are the only surfaces this app prerenders FOR indexing and unfurling " +
      `(decisions § 161), so a missing signal here is the whole point of the page:\n  ${missing.join("\n  ")}`,
  );
});

test("seo.md's `/` row says what the route does, not what it was meant to do", () => {
  // The row read "prerendered (intended -- the artifact is the SPA shell
  // today)" for as long as the surface existed, which is a render map
  // describing a page that was not being served. Anchored to the loader
  // rather than to the sentence: a row that stops agreeing with `+page.ts`
  // fails whichever of the two moved.
  const row = readFileSync(SEO_DOC, "utf8")
    .split("\n")
    .filter((line) => line.startsWith("|"))
    .map((line) => line.split("|").map((c) => c.trim()))
    .filter((cells) => cells[1] === "`/` landing");
  assert.equal(
    row.length,
    1,
    `expected exactly one render-map row for /, found ${row.length}`,
  );
  assert.equal(
    row[0][2].includes("prerendered"),
    /export const prerender\s*=\s*true/.test(readFileSync(ROOT_PAGE, "utf8")),
    `the mode cell disagrees with src/routes/+page.ts; it reads: ${row[0][2]}`,
  );
  assert.ok(
    !/intend|today|SPA shell/i.test(row[0][2]),
    "the mode cell hedges about the artifact; the artifact cases above are what state it: " +
      row[0][2],
  );
});
