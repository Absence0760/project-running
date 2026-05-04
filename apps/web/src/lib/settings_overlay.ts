/// Pure overlay-lookup helper for the universal + per-device prefs
/// bags. Lives in its own module so tests can import it without
/// dragging in `./supabase` (which transitively pulls in the
/// SvelteKit `$env/static/public` virtual import — that breaks the
/// `tsx --test` loader). `settings.ts` re-exports both names.

export type PrefsBag = Record<string, unknown>;

export interface LoadedSettings {
	universal: PrefsBag;
	device: PrefsBag;
}

/// device → universal → fallback. Null and undefined fall through to
/// the next layer; any concrete value (including 0, '', false) wins.
export function effective<T>(
	settings: LoadedSettings,
	key: string,
	fallback?: T,
): T | undefined {
	const fromDevice = settings.device[key];
	if (fromDevice !== undefined && fromDevice !== null) return fromDevice as T;
	const fromUniversal = settings.universal[key];
	if (fromUniversal !== undefined && fromUniversal !== null) return fromUniversal as T;
	return fallback;
}
