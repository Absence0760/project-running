/// Pure mapping from the universal `privacy_default` preference to the
/// `runs.is_public` boolean for a newly-created run. Only `public` yields a
/// public run; `followers` and `private` stay private — runs have no
/// followers-only visibility tier (see docs/settings.md). Mirrors mobile
/// `Preferences.newRunsArePublic` in apps/mobile_android/lib/preferences.dart
/// — keep the two in lockstep.
///
/// Lives in its own supabase-free module so it's unit-testable with
/// `tsx --test` (data.ts pulls in `./supabase` → `$env`, which the tsx
/// loader can't resolve).
export function privacyDefaultToIsPublic(pref: string | null | undefined): boolean {
	return pref === 'public';
}
