import { test } from 'node:test';
import assert from 'node:assert/strict';

import { humaniseUpstreamError } from './providers';

const LOCAL = 'http://127.0.0.1:11434/v1';
const REMOTE = 'https://openrouter.ai/api/v1';

test('Ollama 404 model-not-found → ollama pull hint', () => {
	const body = JSON.stringify({
		error: {
			message: "model 'llama3.1:8b-instruct-q8_0' not found",
			type: 'not_found_error',
		},
	});
	const out = humaniseUpstreamError(404, body, 'llama3.1:8b-instruct-q8_0', LOCAL);
	assert.match(out, /model "llama3\.1:8b-instruct-q8_0"/);
	assert.match(out, /ollama pull llama3\.1:8b-instruct-q8_0/);
	assert.match(out, /ollama list/);
	// Must NOT leak the raw JSON.
	assert.doesNotMatch(out, /not_found_error/);
	assert.doesNotMatch(out, /\{"error"/);
});

test('Remote 404 model-not-found → catalogue hint, no ollama pull', () => {
	const body = JSON.stringify({
		error: { message: 'The model "claude-impossibru" does not exist' },
	});
	const out = humaniseUpstreamError(404, body, 'claude-impossibru', REMOTE);
	assert.match(out, /provider's model catalogue/);
	assert.doesNotMatch(out, /ollama pull/);
	assert.match(out, /COACH_MODEL/);
});

test('401 → API key guidance', () => {
	const out = humaniseUpstreamError(
		401,
		JSON.stringify({ error: { message: 'Invalid API key' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /401/);
	// The 401 helper deliberately stays provider-neutral — naming the
	// specific env var (e.g. OPENAI_API_KEY) leaks which provider the
	// server is wired against to anyone probing the chat error bar.
	// See commit 55e9e81 ("audit: address /audit/all Lows").
	assert.match(out, /upstream API key configuration/);
	assert.doesNotMatch(out, /OPENAI_API_KEY|ANTHROPIC_API_KEY/);
	assert.match(out, /gpt-4o/);
});

test('429 → rate-limit, surfaces upstream message', () => {
	const out = humaniseUpstreamError(
		429,
		JSON.stringify({ error: { message: 'Slow down: 2 req/min cap' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /429/);
	assert.match(out, /Slow down/);
});

test('403 geo-block → distinct region-unavailable message (not a generic upstream error)', () => {
	const out = humaniseUpstreamError(
		403,
		JSON.stringify({ error: { message: 'Country, region, or territory not supported' } }),
		'claude-opus-4-8',
		REMOTE,
	);
	assert.match(out, /region/i);
	assert.doesNotMatch(out, /^Coach upstream 403:/);
	// Must not leak the configured provider/env.
	assert.doesNotMatch(out, /OPENAI_API_KEY|ANTHROPIC_API_KEY/);
});

test('403 with a non-geo message keeps the upstream envelope', () => {
	const out = humaniseUpstreamError(
		403,
		JSON.stringify({ error: { message: 'permission denied for resource' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /403/);
	assert.match(out, /permission denied/);
});

test('Unrecognised status keeps the upstream-style envelope, capped to 300 chars', () => {
	const longMessage = 'x'.repeat(500);
	const out = humaniseUpstreamError(
		500,
		JSON.stringify({ error: { message: longMessage } }),
		'm',
		LOCAL,
	);
	assert.match(out, /^Coach upstream 500: /);
	// 300-char cap on the trailing message.
	const tail = out.replace(/^Coach upstream 500: /, '');
	assert.equal(tail.length, 300);
});

test('Non-JSON body falls through to the raw text', () => {
	const out = humaniseUpstreamError(503, '<html>bad gateway</html>', 'm', REMOTE);
	assert.match(out, /^Coach upstream 503: /);
	assert.match(out, /bad gateway/);
});

test('404 without "model" in the message falls through to the generic envelope', () => {
	// The model-not-found branch requires BOTH a 404 status AND the
	// upstream message containing the word "model" + a not-found
	// phrase. A 404 from a typoed URL ("Endpoint /v1/widgets does not
	// exist") shouldn't masquerade as a missing model.
	const out = humaniseUpstreamError(
		404,
		JSON.stringify({ error: { message: 'Endpoint /v1/widgets does not exist' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /^Coach upstream 404: /);
	assert.doesNotMatch(out, /Coach can't reach model/);
});
