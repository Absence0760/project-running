package internal

import (
	"context"
	"log/slog"
)

// DigestBuilderBackend is the narrow Supabase surface the weekly-digest
// builder needs: select the opted-in recipients, enqueue one job each.
// *SupabaseClient satisfies it; tests substitute a fake.
type DigestBuilderBackend interface {
	FetchDigestCandidates(ctx context.Context, limit int) ([]string, error)
	EnqueueWeeklyDigest(ctx context.Context, userID string) error
}

// maxDigestCandidatesPerRun bounds one builder pass. The per-recipient
// handler is cheap, but capping the fan-out keeps a single run's enqueue
// burst bounded; a larger opted-in population is drained across runs.
const maxDigestCandidatesPerRun = 5000

// EnqueueAllWeeklyDigests is the weekly-digest BUILDER — it selects every
// opted-in (user_settings.prefs.email_weekly_digest='on') recipient and
// enqueues one `weekly_digest` job per id. The handler re-checks the opt-in
// AND the suppression list per recipient (defence in depth — either can flip
// between enqueue and send), so a stale candidate here is harmless.
//
// ─────────────────────────────────────────────────────────────────────────
// GATE: this function is deliberately UNSCHEDULED. Nothing calls it on a
// timer. Wiring a weekly pg_cron schedule (or any always-on dispatcher) that
// invokes it is a SEPARATE, CISO + counsel-gated step — bulk/promotional
// mail under CAN-SPAM + GDPR/ePrivacy, unlike the transactional kinds. Do
// NOT add a pg_cron entry, a cron HTTP endpoint, or a goroutine ticker that
// calls this until that sign-off lands. See docs/features/email.md
// § Engagement.
// ─────────────────────────────────────────────────────────────────────────
//
// Returns the number of jobs enqueued. A per-recipient enqueue failure is
// logged and skipped rather than aborting the whole run — one bad row
// shouldn't strand every other recipient's digest.
func EnqueueAllWeeklyDigests(ctx context.Context, be DigestBuilderBackend, log *slog.Logger) (int, error) {
	candidates, err := be.FetchDigestCandidates(ctx, maxDigestCandidatesPerRun)
	if err != nil {
		return 0, err
	}
	enqueued := 0
	for _, uid := range candidates {
		if err := be.EnqueueWeeklyDigest(ctx, uid); err != nil {
			if log != nil {
				log.Warn("weekly_digest builder: enqueue failed; skipping recipient", "user_id", uid, "err", err)
			}
			continue
		}
		enqueued++
	}
	if log != nil {
		log.Info("weekly_digest builder: enqueued jobs", "candidates", len(candidates), "enqueued", enqueued)
	}
	return enqueued, nil
}
