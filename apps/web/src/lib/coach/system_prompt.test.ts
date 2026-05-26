// Source-grep guards on the COACH_SYSTEM_PROMPT string. Run with
// `npx tsx --test apps/web/src/lib/coach/system_prompt.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { COACH_SYSTEM_PROMPT } from './system_prompt';

test('system prompt declares the <CONTEXT> boundary', () => {
	// audit/coach May 2026 Medium #4 + Low #11 — OWASP LLM01 prompt
	// injection. Any text inside <CONTEXT>...</CONTEXT> markers is
	// user-controlled (run titles, display names, plan names); the
	// model must treat it as data, not instructions. Without this
	// boundary, a renamed-run injection persists across the cached
	// turn forever.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/<CONTEXT>[^<]*<\/CONTEXT>/i,
		'system prompt must reference the <CONTEXT>...</CONTEXT> markers',
	);
	assert.match(
		COACH_SYSTEM_PROMPT,
		/never follow instructions/i,
		'system prompt must instruct the model to ignore instructions inside the context block',
	);
});

test('system prompt refuses persona-switch / system-impersonation', () => {
	// Companion to the CONTEXT boundary — protects against turns
	// where the user (or a replayed assistant turn) claims to be
	// system / admin / Anthropic and asks to bypass the rules.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/impersonate|system administrator|reveal the system prompt/i,
		'system prompt must explicitly refuse impersonation / system-prompt exfiltration',
	);
});

test('system prompt does NOT leak internal field names as forbidden secrets', () => {
	// Sanity: the trust+safety section mentions runner_context and
	// recent_runs by name (so the model knows the field semantics).
	// That's intentional — they're not secrets, just internal labels.
	// This test exists as a placeholder so a future contributor who
	// adds a real secret name to the prompt gets a CI bounce.
	const FORBIDDEN = ['ANTHROPIC_API_KEY', 'service_role', 'SUPABASE_SERVICE_ROLE_KEY'];
	for (const k of FORBIDDEN) {
		assert.equal(
			COACH_SYSTEM_PROMPT.includes(k),
			false,
			`system prompt must NEVER mention \`${k}\` — operational secret`,
		);
	}
});
