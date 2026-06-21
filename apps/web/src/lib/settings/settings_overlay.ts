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

/// Resolve the effective distance unit for the app-wide `setUnit` signal.
///
/// `preferred_unit` is a UD-scope key — a device override (set on
/// `/settings/devices`) beats the universal bag, which beats the legacy
/// `user_profiles.preferred_unit` column. The auth store can only see the
/// profile column, so feeding `setUnit` from it alone makes a per-device
/// override silently dead (a browser set to 'mi' still renders km). This
/// folds the bags on top of the column. Anything other than the literal
/// 'mi' resolves to 'km' — the same normalisation `setUnit` applies.
export function effectivePreferredUnit(
	settings: LoadedSettings,
	columnFallback?: string | null,
): 'km' | 'mi' {
	const resolved = effective<string>(settings, 'preferred_unit', columnFallback ?? undefined);
	return resolved === 'mi' ? 'mi' : 'km';
}
