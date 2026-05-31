/**
 * The label shown for the signed-in user's own account chip (sidebar
 * footer + its sign-out popover).
 *
 * When `display_name` is null the chip must NOT fall back to the auth
 * email: on a shared or a partner's device that surfaces the runner's
 * legal-name email as the prominent identifier. The popover already fell
 * back to the neutral `'Account'`; the sidebar button, its aria-label,
 * and its title fell back to the email instead — the two surfaces had
 * drifted. Route every site through this one helper so they can't drift
 * again. The email still renders on the dedicated secondary `.user-email`
 * / `.popover-email` line, matching every account-chip convention.
 */
export function accountLabel(displayName: string | null | undefined): string {
	const trimmed = displayName?.trim();
	return trimmed && trimmed.length > 0 ? trimmed : 'Account';
}
