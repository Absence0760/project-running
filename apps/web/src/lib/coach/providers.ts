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
			throw new Error(`coach upstream ${res.status}: ${errText.slice(0, 400)}`);
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
