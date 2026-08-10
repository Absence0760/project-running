// The backup / restore buttons used to render the raw progress stage —
// "runs...", "profile...", "writing..." — as their label, identically in
// all six locales. These are wire identifiers, not copy.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { transferStageKey, type TransferStage } from './stage_labels';

const STAGES: TransferStage[] = [
	'reading',
	'profile',
	'runs',
	'tracks',
	'routes',
	'writing',
	'done',
];

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('every stage the two progress unions can report maps to a key', () => {
	// The union is derived from BackupProgress / RestoreProgress, so a new
	// stage on either fails Record<TransferStage, MessageKey> at build time
	// — this checks the runtime side of the same promise.
	const seen = new Set<string>();
	for (const stage of STAGES) {
		const key = transferStageKey(stage);
		assert.ok(key, `${stage} has no message key`);
		assert.ok(!seen.has(key), `${key} is reused by more than one stage`);
		seen.add(key);
	}
});

test('the stages the emitters actually fire are all covered', () => {
	// Reason: the union is a type, so a stage literal that drifts in an
	// emitter without the type being updated would not be caught. Scrape
	// the emitters for the literals they pass.
	const sources = [
		read('src/lib/backup/backup.ts'),
		read('src/lib/backup/backup_writer.ts'),
		read('src/lib/backup/restore_orchestrator.ts'),
	].join('\n');
	const emitted = new Set(
		[...sources.matchAll(/stage: '([a-z]+)'/g)].map((match) => match[1]),
	);
	assert.ok(emitted.size > 0, 'found no stage literals — did the emitters change shape?');
	for (const stage of emitted) {
		assert.ok(
			(STAGES as string[]).includes(stage),
			`stage '${stage}' is emitted but has no label`,
		);
	}
});

test('every stage label is localized in all six catalogues', () => {
	for (const locale of ['en', 'de', 'es', 'fr', 'ja', 'pt-BR']) {
		const catalogue = read(`src/lib/i18n/locales/${locale}.ts`);
		for (const stage of STAGES) {
			const key = transferStageKey(stage);
			assert.ok(catalogue.includes(`"${key}":`), `${key} missing from ${locale}.ts`);
		}
	}
});

test('the account page renders the label, not the raw stage', () => {
	const source = read('src/routes/settings/account/+page.svelte');
	assert.doesNotMatch(
		source,
		/\$\{(backupProgress|restoreProgress)\.stage\}/,
		'the raw stage identifier must not reach the button label',
	);
	assert.match(source, /m\(transferStageKey\(backupProgress\.stage\)\)/);
	assert.match(source, /m\(transferStageKey\(restoreProgress\.stage\)\)/);
});
