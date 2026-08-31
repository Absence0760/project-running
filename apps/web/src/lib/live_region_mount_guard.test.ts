// A live region only announces what changes while it is already mounted
// (decisions.md § 736). A region and its first message arriving in ONE DOM
// mutation is not a change made inside the region — it is the region's own
// arrival — and assistive technology announces nothing.
//
// § 736 fixed `ToastContainer` and `security_guards.test.ts` pins that one
// component. § 797 then shipped the identical shape on `/routes/new`'s
// "preference not applied" note and had to correct it before merge: the one
// message on that page whose entire job is disclosure was announced to
// nobody. Two instances of one class in five days is the argument for a scan
// rather than a third per-component guard.
//
// The rule is mechanical and narrow on purpose: an element carrying a live
// `aria-live` must not be the FIRST element a conditional block opens. That
// is exactly the "region and text in one mutation" shape. A region mounted
// with the surrounding panel and later filled — `/routes/new`'s note inside
// the distance-target panel, nutrition's budget head inside its card — is a
// different thing and is correctly silent about the panel and loud about the
// text, so the scan leaves it alone.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..');

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			if (entry === 'node_modules') continue;
			svelteFiles(full, out);
		} else if (entry.endsWith('.svelte')) {
			out.push(full);
		}
	}
	return out;
}

/// Blank every `<script>` / `<style>` block and every comment, preserving
/// line numbering so a report names the file's own line.
function markupOnly(raw: string): string {
	const lines = raw.split('\n');
	const kept: string[] = [];
	let skipping: 'script' | 'style' | 'comment' | null = null;
	for (const line of lines) {
		const lower = line.toLowerCase();
		if (skipping === 'script' || skipping === 'style') {
			if (lower.includes(`</${skipping}`)) skipping = null;
			kept.push('');
			continue;
		}
		if (skipping === 'comment') {
			if (line.includes('-->')) skipping = null;
			kept.push('');
			continue;
		}
		if (lower.includes('<script')) {
			if (!lower.includes('</script')) skipping = 'script';
			kept.push('');
			continue;
		}
		if (lower.includes('<style')) {
			if (!lower.includes('</style')) skipping = 'style';
			kept.push('');
			continue;
		}
		if (line.includes('<!--')) {
			if (!line.includes('-->')) skipping = 'comment';
			kept.push('');
			continue;
		}
		kept.push(line);
	}
	return kept.join('\n');
}

const OPENS_A_BRANCH = /^\{(#if|:else)\b/;
const LIVE_ATTR = /aria-live=(["'])(polite|assertive)\1/;

/// Every place a conditional block's FIRST element carries a live aria-live,
/// as `path:line`.
export function regionsMountedByABranch(source: string): number[] {
	const lines = markupOnly(source).split('\n');
	const hits: number[] = [];
	for (let i = 0; i < lines.length; i++) {
		if (!OPENS_A_BRANCH.test(lines[i].trim())) continue;
		let j = i + 1;
		while (j < lines.length && lines[j].trim() === '') j++;
		if (j >= lines.length) continue;
		const first = lines[j].trim();
		// Only an element opening counts. Text, an interpolation or a nested
		// block start is not the shape (the region, if any, comes later and is
		// therefore not what the branch mounts).
		if (!first.startsWith('<') || first.startsWith('</')) continue;
		// The opening tag may span lines; read to its `>`.
		let tag = '';
		let k = j;
		while (k < lines.length && !tag.includes('>')) {
			tag += lines[k] + '\n';
			k++;
		}
		tag = tag.slice(0, tag.indexOf('>') + 1);
		if (LIVE_ATTR.test(tag)) hits.push(j + 1);
	}
	return hits;
}

test('no live region is mounted by the same conditional that supplies its text', () => {
	const offenders: string[] = [];
	for (const file of svelteFiles(SRC)) {
		const source = readFileSync(file, 'utf-8');
		if (!LIVE_ATTR.test(source)) continue;
		for (const line of regionsMountedByABranch(source)) {
			offenders.push(`${relative(SRC, file)}:${line}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'These aria-live regions enter the accessibility tree together with their ' +
			'first message, so nothing is announced (decisions.md § 736). Mount the ' +
			'region unconditionally and let only its contents change:\n  ' +
			offenders.join('\n  '),
	);
});

test('the scan sees the shape it bans and spares the ones it must not', () => {
	// § 738: a scan is the only instrument that can see this class, so probe
	// it in both directions rather than trusting it by reading.
	const caught = `
<main>
	{#if info}
		<div class="info" role="status" aria-live="polite">{info}</div>
	{/if}
</main>`;
	assert.equal(regionsMountedByABranch(caught).length, 1);

	const caughtMultiline = `
{#if isOffline}
	<div
		class="banner"
		aria-live="polite"
	>text</div>
{/if}`;
	assert.equal(regionsMountedByABranch(caughtMultiline).length, 1);

	const caughtElseBranch = `
{#if a}
	<p>plain</p>
{:else if b}
	<p aria-live="assertive">boom</p>
{/if}`;
	assert.equal(regionsMountedByABranch(caughtElseBranch).length, 1);

	// Permanently mounted, contents conditional — the § 736 remedy.
	const spared = `
<div class="stack" aria-live="polite">
	{#if toast}
		<span>{toast.text}</span>
	{/if}
</div>`;
	assert.equal(regionsMountedByABranch(spared).length, 0);

	// Mounted with a surrounding panel it is not the announcement for.
	const sparedPanel = `
{#if showPanel}
	<div class="panel">
		<button>Generate</button>
		<p aria-live="polite">{note}</p>
	</div>
{/if}`;
	assert.equal(regionsMountedByABranch(sparedPanel).length, 0);

	// `aria-live="off"` is not a live region and must never be reported.
	const sparedOff = `
{#if open}
	<div aria-live="off">{log}</div>
{/if}`;
	assert.equal(regionsMountedByABranch(sparedOff).length, 0);

	// Prose in a comment must not be read as markup.
	const sparedComment = `
<!--
	{#if info}
		<div aria-live="polite">{info}</div>
	{/if}
-->
<div aria-live="polite">{info}</div>`;
	assert.equal(regionsMountedByABranch(sparedComment).length, 0);
});
