import { expect, test } from '@playwright/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * AI-coach conversation-LIFECYCLE journey — one fresh runner walks the
 * full "an active multi-turn thread exists → I read the grounded-context
 * strip → I re-scope what the coach loads (runs window + plan) → I retire
 * the thread (archive) → it leaves the active list and lands in History →
 * I delete it forever" arc, end to end in one test.
 *
 * What the per-surface specs already pin (and this one therefore does NOT
 * re-prove):
 *   - page.spec.ts: SSE send/stream/error paths, the chip dropdowns in
 *     isolation, the daily-cap 429/empty-stream edge cases.
 *   - coach-grounded-journey.spec.ts: the grounding *wire* contract — that
 *     the runs window / plan the strip shows is the window/plan POSTed to
 *     /api/coach (it stubs the SSE endpoint + captures the body).
 *   - archive-delete.spec.ts: the Cancel-keeps / Confirm-deletes
 *     ConfirmDialog on an already-archived conversation.
 *
 * The genuinely-uncovered STITCHED slice this covers: the *transition*
 * from a live active thread to an archived one and out — i.e. archiving
 * the CURRENT conversation (the "New chat" affordance, which routes
 * through the start-new ConfirmDialog), watching the multi-turn active
 * thread leave the active list, reappear as a History row with the right
 * message count, and then deleting that freshly-archived row. archive-
 * delete.spec.ts starts from a pre-seeded archive; it never exercises the
 * active→archived hop. No existing spec drives archive-of-the-current-
 * thread, nor checks the active row's "Active · N" count tracks a
 * multi-message planted thread.
 *
 * LLM: NOT driven. A real send needs ANTHROPIC_API_KEY and is the sole
 * server-side writer of coach_messages, so we PLANT a two-turn active
 * thread (user+assistant) via the service-role admin client and exercise
 * render → archive → History → delete against those persisted rows. This
 * keeps the journey deterministic and free of any provider call. The
 * persistence contract is therefore proven against a real backend round-
 * trip (the planted rows load via loadThread), and the archive/delete
 * mutations are the component's own real Supabase writes under the user's
 * JWT — only the assistant *generation* is skipped.
 *
 * Subject: an EPHEMERAL saga user (createSagaUsers) so the shared seeded
 * users' coach state is never touched. The chat is render-gated behind the
 * first-use AI-coach consent disclosure (coach_consent_at on
 * user_profiles); a fresh saga user hasn't consented, so we stamp it via
 * the server-authoritative record_coach_consent() RPC under the user's
 * OWN JWT in setup — without it the composer / context strip never render.
 * (We also pre-accept the cookie banner via addInitScript, distinct from
 * the AI-coach consent.) The thread is planted no-plan (plan_id null) and
 * the page opened at ?plan=none so the component's null plan-scope matches.
 */

const PLAN_NULL_URL = '/coach?plan=none';

function setConsentAccepted() {
	localStorage.setItem(
		'cookie_consent',
		JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
	);
}

test.describe('AI coach — conversation lifecycle (active → archive → History → delete)', () => {
	let user: SagaUser;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Coach Lifecycle'] });
	});

	test.afterAll(async () => {
		if (user) await deleteSagaUsers([user]);
	});

	test('plant a two-turn active thread → archive the current conversation → it lands in History with the right count → delete it forever', async ({
		browser,
	}) => {
		const admin = getAdminClient();

		// The planted active (non-archived) user turn becomes the thread
		// title + the .bubble.user; the assistant turn renders as a non-user
		// .bubble. A unique marker keeps the locators precise across reruns.
		const marker = Date.now();
		const USER_Q = `lifecycle ${marker}: what should my taper week look like?`;
		const ASSISTANT_A = `Taper marker ${marker}: cut volume ~40%, keep some intensity.`;

		const ctx = await browser.newContext({ storageState: user.storageStatePath });
		// Distinct from the AI-coach consent: pre-accept the GDPR cookie
		// banner so it can't float over the composer / context strip.
		await ctx.addInitScript(setConsentAccepted);
		const page = await ctx.newPage();

		try {
			// ── Setup: stamp AI-coach consent + plant a no-plan active thread ──
			await test.step('stamp coach consent (RPC, user JWT) + plant a two-turn active thread', async () => {
				// record_coach_consent() is the only sanctioned writer of
				// coach_consent_at (server now(), first-stamp-wins) — call it
				// under the user's own JWT so the chat clears its render gate.
				const userClient = await getUserClient({
					email: user.email,
					password: user.password,
				});
				const { error: consentErr } = await userClient.rpc('record_coach_consent');
				expect(consentErr).toBeNull();

				// Plant the active thread service-role (assistant rows are
				// service-role-only writes per the XSS-audit RLS — a planted
				// pair is the only way to render an assistant bubble without a
				// live model call). plan_id null so the page's ?plan=none scope
				// resolves to the same thread.
				const { error: seedErr } = await admin.from('coach_messages').insert([
					{
						user_id: user.id,
						plan_id: null,
						role: 'user',
						content: USER_Q,
						created_at: '2026-05-20T08:00:00.000Z',
					},
					{
						user_id: user.id,
						plan_id: null,
						role: 'assistant',
						content: ASSISTANT_A,
						created_at: '2026-05-20T08:00:04.000Z',
					},
				]);
				expect(seedErr).toBeNull();
			});

			// ── 1. The planted active thread hydrates from the backend ──────
			await test.step('the active thread loads (both turns render) past the consent gate', async () => {
				await page.goto(PLAN_NULL_URL);

				// Composer present == the consent gate cleared + the chat mounted.
				await expect(page.getByPlaceholder(/Ask about today/)).toBeVisible({
					timeout: 15_000,
				});

				// Both planted turns render — proving loadThread hydrated from
				// coach_messages (a real backend read), not from a stub.
				await expect(
					page.locator('.bubble.user', { hasText: USER_Q }),
				).toBeVisible({ timeout: 10_000 });
				await expect(
					page.locator('.bubble', { hasText: ASSISTANT_A }),
				).toBeVisible();
			});

			// ── 2. The grounded-context strip + the active sidebar row ──────
			await test.step('the grounded strip shows no-plan + a runs chip, and the active row counts the planted turns', async () => {
				// A fresh saga user has no plan: the plan chip is the muted
				// "No plan" chip (no switcher, since plans=[]), and with no runs
				// the recent-runs slot is the muted "no runs" chip.
				const strip = page.locator('.context-strip');
				await expect(strip).toBeVisible({ timeout: 10_000 });
				// The "No plan" label shares its chip span with a material-symbols
				// icon ligature ("calendar_month"), so an exact getByText can't
				// match — scope to the muted chip and match the substring.
				await expect(
					strip.locator('.chip-muted', { hasText: 'No plan' })
				).toBeVisible();

				// Open the conversation sidebar and read the active row's
				// "Active · 2" meta — it mirrors the loaded message count.
				await page
					.getByRole('button', { name: /Show conversations|Hide conversations/i })
					.click();
				const activeRow = page.locator('.shell aside.sidebar .thread-row.active');
				await expect(activeRow).toContainText('Active');
				await expect(activeRow).toContainText('· 2');
				// The active row's title is the first user turn (truncated).
				await expect(activeRow.locator('.thread-title')).toContainText(
					`lifecycle ${marker}`,
				);
			});

			// ── 3. Re-scope what the coach loads: switch the runs window ─────
			await test.step('switching the runs window updates the strip chip (re-scopes the grounding)', async () => {
				// With zero runs the strip shows the muted no-runs chip instead
				// of the runs ChipDropdown, so the runs-window switcher isn't
				// available for this fresh user. Plant a run so the dropdown
				// appears, then re-scope it.
				const { error: runErr } = await admin.from('runs').insert({
					user_id: user.id,
					started_at: '2026-05-19T07:00:00.000Z',
					distance_m: 8000,
					duration_s: 2400,
					source: 'app',
				});
				expect(runErr).toBeNull();

				// Reload so loadContextSummary re-counts runs and swaps the
				// muted chip for the live runs-window dropdown.
				await page.reload();
				const runsTrigger = page.getByRole('button', {
					name: 'Recent runs to include',
				});
				await expect(runsTrigger).toBeVisible({ timeout: 10_000 });
				// Default window is Last 20 (DEFAULT_RUNS_LIMIT in CoachChat).
				await expect(runsTrigger).toContainText('Last 20');

				await runsTrigger.click();
				const popover = page.locator('[role="listbox"]');
				await expect(popover).toBeVisible({ timeout: 5_000 });
				// exact:true so "Last 50" doesn't also match "Last 500".
				await popover.getByRole('option', { name: 'Last 50', exact: true }).click();
				await expect(popover).toHaveCount(0);
				await expect(runsTrigger).toContainText('Last 50');
			});

			// ── 4. Archive the CURRENT conversation via "New chat" ──────────
			await test.step('"New chat" archives the live thread through the confirm dialog', async () => {
				// Re-open the sidebar (the reload above collapsed it) and click
				// "New chat" — with a non-empty active thread this raises the
				// start-new ConfirmDialog rather than firing immediately.
				await page
					.getByRole('button', { name: /Show conversations|Hide conversations/i })
					.click();
				const sidebar = page.locator('.shell aside.sidebar');
				await sidebar.getByRole('button', { name: /New chat/i }).click();

				const dialog = page.locator('.modal', { hasText: 'Start a new conversation?' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Start new' }).click();

				// The active thread is now empty — the planted turns no longer
				// render in the chat body, and the active row shows no count.
				await expect(
					page.locator('.bubble.user', { hasText: USER_Q }),
				).toHaveCount(0, { timeout: 10_000 });
				const activeRow = page.locator('.shell aside.sidebar .thread-row.active');
				await expect(activeRow).toContainText('Active');
				await expect(activeRow).not.toContainText('· 2');
			});

			// ── 5. The archived thread shows up in History with its count ───
			await test.step('the archived conversation lands as a History row carrying the 2-message count', async () => {
				// The retired thread is now an .archive-row in the sidebar,
				// titled by its first user turn + a "· 2" message count.
				const archiveRow = page.locator('.archive-row', {
					hasText: `lifecycle ${marker}`,
				});
				await expect(archiveRow).toBeVisible({ timeout: 10_000 });
				await expect(archiveRow.locator('.thread-meta')).toContainText('· 2');

				// Opening it switches the chat into read-only archive view: the
				// planted turns render again and the read-only banner appears.
				await archiveRow.click();
				await expect(
					page.locator('.bubble', { hasText: ASSISTANT_A }),
				).toBeVisible({ timeout: 10_000 });
				await expect(page.locator('.archive-banner')).toContainText(/read-only/i);

				// Return to the active (now-empty) thread.
				await page.getByRole('button', { name: /Back to active/i }).click();
				await expect(page.locator('.archive-banner')).toHaveCount(0);
			});

			// ── 6. Delete the freshly-archived conversation forever ─────────
			await test.step('deleting the archived conversation removes it from History', async () => {
				const archiveRow = page.locator('.archive-row', {
					hasText: `lifecycle ${marker}`,
				});
				await expect(archiveRow).toBeVisible({ timeout: 10_000 });

				await archiveRow.getByRole('button', { name: 'Delete archive' }).click();
				const dialog = page.locator('.modal', { hasText: 'Delete this conversation?' });
				await expect(dialog).toBeVisible({ timeout: 10_000 });
				await dialog.getByRole('button', { name: 'Delete forever' }).click();

				// Row gone from the sidebar...
				await expect(archiveRow).toHaveCount(0, { timeout: 10_000 });

				// ...and gone from the backend — both planted rows deleted.
				const { count } = await admin
					.from('coach_messages')
					.select('id', { count: 'exact', head: true })
					.eq('user_id', user.id);
				expect(count ?? 0).toBe(0);
			});
		} finally {
			// Teardown: drop every coach_messages row + the planted run for
			// this saga user. The consent stamp + user_profiles row are removed
			// when deleteSagaUsers CASCADE-drops the auth.users row in afterAll.
			await admin.from('coach_messages').delete().eq('user_id', user.id);
			await admin.from('runs').delete().eq('user_id', user.id);
			await ctx.close();
		}
	});
});
