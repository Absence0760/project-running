import { readFileSync } from 'node:fs';

import { expect, test } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * Plan import / export (roadmap Phase 3 — Sharing & handoff + Import).
 * The Markdown/JSON serialize round-trip is unit-tested; this pins the
 * UI wiring: the export menu on /plans/[id] produces a file, and the
 * paste-import on /plans/new parses a table into the editable preview.
 *
 * The import test stops at the preview (doesn't submit) so it never
 * flips USER_A's seeded active plan to completed — other specs rely on
 * Richmond Half 2026 staying active.
 */

test.describe('plan import / export', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('export menu downloads a Markdown plan with the workout table', async ({ page }) => {
		await page.goto('/plans');
		await page.getByRole('link', { name: /Richmond Half 2026/ }).click();
		await expect(page.getByRole('heading', { level: 1, name: /Richmond Half 2026/ }))
			.toBeVisible({ timeout: 10_000 });

		// Open the Export disclosure, then trigger the .md download.
		await page.locator('.export-menu summary').click();
		const [download] = await Promise.all([
			page.waitForEvent('download'),
			page.getByRole('menuitem', { name: /Download \.md/ }).click(),
		]);
		const path = await download.path();
		const content = readFileSync(path, 'utf-8');
		expect(content).toMatch(/^# Richmond Half 2026/m);
		expect(content).toMatch(/\| Week \| Date \| Type \| Distance \| Pace \| Notes \|/);
		// At least one data row (a date cell).
		expect(content).toMatch(/\|\s*1\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|/);
	});

	test('paste-import parses a Markdown table into the editable preview', async ({ page }) => {
		await page.goto('/plans/new');
		// The generator shows a default (half-marathon) outline first.
		await expect(page.locator('.week-item').first()).toBeVisible({ timeout: 10_000 });

		const md = [
			'# Imported e2e plan',
			'- Goal event: distance_10k',
			'- Start date: 2026-08-02',
			'',
			'| Week | Date | Type | Distance | Pace | Notes |',
			'| --- | --- | --- | --- | --- | --- |',
			'| 1 | 2026-08-02 | long | 14.00 km | 6:00 | base |',
			'| 1 | 2026-08-04 | easy | 8.00 km | 6:30 | |',
			'| 2 | 2026-08-09 | long | 16.00 km | 6:00 | |',
		].join('\n');

		await page.getByText('Import a plan', { exact: true }).click();
		await page.locator('.import-text').fill(md);
		await page.getByRole('button', { name: 'Load plan' }).click();

		// Import mode note appears and the preview collapses to the 2
		// imported weeks (vs the generator's ~12-week default).
		await expect(page.locator('.imported-note')).toBeVisible();
		await expect(page.locator('.week-item')).toHaveCount(2);
		// Name field picked up the parsed title.
		await expect(page.locator('input[type="text"]').first()).toHaveValue('Imported e2e plan');
	});
});
