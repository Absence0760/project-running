// Provider-specific streaming. Both providers conform to the
// `ProviderStream` shape so handler.ts is provider-agnostic.

import Anthropic from '@anthropic-ai/sdk';
import type { ProviderStream, ProviderUsage, Tier } from './types';
import { TIER_LIMITS, emptyUsage } from './types';

// ─────────────────────── Anthropic (streaming + prompt cache) ───────────────────────

export function streamAnthropic(
	apiKey: string,
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	limits: typeof TIER_LIMITS[Tier],
): ProviderStream {
	const anthropic = new Anthropic({ apiKey });

	const systemBlocks = [
		{
			type: 'text' as const,
			text: systemText,
			cache_control: { type: 'ephemeral' as const },
		},
	];

	const convo = [
		{
			role: 'user' as const,
			content: [
				{
					type: 'text' as const,
					text: contextPayload,
					cache_control: { type: 'ephemeral' as const },
				},
			],
		},
		{
			role: 'assistant' as const,
			content: 'Got it — I have your plan and recent runs in view. Ask away.',
		},
		...messages.map((m) => ({
			role: m.role,
			content: [{ type: 'text' as const, text: m.content }],
		})),
	];

	const stream = anthropic.messages.stream({
		model: 'claude-sonnet-4-5',
		max_tokens: limits.maxTokens,
		system: systemBlocks,
		messages: convo,
	});

	async function* tokens(): AsyncIterable<string> {
		for await (const event of stream) {
			if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
				yield event.delta.text;
			}
		}
	}

	return {
		tokens: tokens(),
		finalUsage: async () => {
			const final = await stream.finalMessage();
			return {
				cache_creation_input_tokens: final.usage.cache_creation_input_tokens ?? 0,
				cache_read_input_tokens: final.usage.cache_read_input_tokens ?? 0,
				input_tokens: final.usage.input_tokens,
				output_tokens: final.usage.output_tokens,
			};
		},
	};
}

// ─────────────────────── OpenAI-compatible (streaming) ───────────────────────

export function streamOpenAI(
	baseUrl: string,
	apiKey: string,
	model: string,
	systemText: string,
	contextPayload: string,
	messages: { role: 'user' | 'assistant'; content: string }[],
	limits: typeof TIER_LIMITS[Tier],
): ProviderStream {
	const convo = [
		{ role: 'system', content: systemText },
		{ role: 'user', content: contextPayload },
		{ role: 'assistant', content: 'Got it — I have your plan and recent runs in view. Ask away.' },
		...messages.map((m) => ({ role: m.role, content: m.content })),
	];

	const usage: ProviderUsage = emptyUsage();
	const finalUsageDeferred: { resolve: (u: ProviderUsage) => void; reject: (e: Error) => void } = {
		resolve: () => {},
		reject: () => {},
	};
	const finalUsagePromise = new Promise<ProviderUsage>((resolve, reject) => {
		finalUsageDeferred.resolve = resolve;
		finalUsageDeferred.reject = reject;
	});

	async function* tokens(): AsyncIterable<string> {
		const res = await fetch(`${baseUrl.replace(/\/$/, '')}/chat/completions`, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				authorization: `Bearer ${apiKey}`,
			},
			body: JSON.stringify({
				model,
				messages: convo,
				max_tokens: limits.maxTokens,
				stream: true,
			}),
		});
		if (!res.ok || !res.body) {
			const errText = await res.text().catch(() => '');
			finalUsageDeferred.resolve(usage);
			throw new Error(humaniseUpstreamError(res.status, errText, model, baseUrl));
		}
		const reader = res.body.getReader();
		const decoder = new TextDecoder();
		let buffer = '';
		try {
			while (true) {
				const { value, done } = await reader.read();
				if (done) break;
				buffer += decoder.decode(value, { stream: true });
				let nl: number;
				while ((nl = buffer.indexOf('\n')) !== -1) {
					const line = buffer.slice(0, nl).trim();
					buffer = buffer.slice(nl + 1);
					if (!line.startsWith('data:')) continue;
					const payload = line.slice(5).trim();
					if (payload === '[DONE]') continue;
					try {
						const j = JSON.parse(payload) as {
							choices?: { delta?: { content?: string } }[];
							usage?: { prompt_tokens?: number; completion_tokens?: number };
						};
						const delta = j.choices?.[0]?.delta?.content;
						if (delta) yield delta;
						if (j.usage) {
							usage.input_tokens = j.usage.prompt_tokens ?? usage.input_tokens;
							usage.output_tokens = j.usage.completion_tokens ?? usage.output_tokens;
						}
					} catch (_) {
						/* malformed line — skip */
					}
				}
			}
		} finally {
			finalUsageDeferred.resolve(usage);
		}
	}

	return {
		tokens: tokens(),
		finalUsage: () => finalUsagePromise,
	};
}

/// Turn an OpenAI-compatible upstream error response into a sentence
/// the chat can show without the raw JSON. Keeps the original
/// `coach upstream <status>: …` shape for unrecognised errors so the
/// caller still sees the raw payload during local debugging, but
/// substitutes a friendly explanation for the cases that come up
/// often: model-not-found (Ollama / OpenRouter when COACH_MODEL is
/// stale) and 401 (bad / missing key).
///
/// Exported so the unit test in `providers.test.ts` can pin every
/// branch without spinning up a real fetch.
export function humaniseUpstreamError(
	status: number,
	rawBody: string,
	model: string,
	baseUrl: string,
): string {
	let parsedMessage: string | null = null;
	try {
		const parsed = JSON.parse(rawBody) as {
			error?: { message?: string; type?: string };
		};
		const m = parsed?.error?.message;
		if (typeof m === 'string' && m.length > 0) parsedMessage = m;
	} catch {
		/* not JSON — fall back to the raw text below */
	}

	// Model-not-found is the recurring local-Ollama footgun: COACH_MODEL
	// is set to something that hasn't been pulled, or the env was
	// switched without the operator pulling the new tag. Detect by
	// status (404) AND the error message mentioning the model name.
	const isLocal = /127\.0\.0\.1|localhost/.test(baseUrl);
	const looksModelMissing =
		status === 404 &&
		parsedMessage != null &&
		/model.*\b(not\s+found|does\s+not\s+exist|unknown)\b/i.test(parsedMessage);
	if (looksModelMissing) {
		const cmd = isLocal
			? `\`ollama pull ${model}\``
			: `your provider's model catalogue (current value: ${model})`;
		return (
			`Coach can't reach model "${model}". ` +
			(isLocal
				? `Pull it locally with ${cmd}, or unset COACH_PROVIDER (or set COACH_MODEL to one you've already pulled — \`ollama list\`).`
				: `Check ${cmd} and update COACH_MODEL accordingly.`)
		);
	}

	if (status === 401) {
		return (
			`Coach upstream rejected the request (401 unauthorized). ` +
			`Check the upstream API key configuration and that it has access to model "${model}".`
		);
	}

	if (status === 429) {
		return (
			`Coach upstream is rate-limiting (429). ` +
			(parsedMessage ?? 'Wait a moment and try again, or switch provider.')
		);
	}

	// Unrecognised — keep the original shape so a developer can still
	// see the upstream payload. Cap to keep the chat-error bar tight.
	const summary = parsedMessage ?? rawBody;
	return `Coach upstream ${status}: ${summary.slice(0, 300)}`;
}
