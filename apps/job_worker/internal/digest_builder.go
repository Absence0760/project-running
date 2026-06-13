package internal

import (
	"context"
	"log/slog"
)

// DigestBuilderBackend is the narrow Supabase surface the weekly-digest
// builder needs: select the opted-in recipients, then bulk-enqueue the
// jobs in chunks. *SupabaseClient satisfies it; tests substitute a fake.
type DigestBuilderBackend interface {
	FetchDigestCandidates(ctx context.Context, limit int) ([]string, error)
	EnqueueWeeklyDigests(ctx context.Context, userIDs []string) error
}

// maxDigestCandidatesPerRun bounds one builder pass. The per-recipient
// handler is cheap, but capping the fan-out keeps a single run's enqueue
// burst bounded; a larger opted-in population is drained across runs.
const maxDigestCandidatesPerRun = 5000

// digestEnqueueChunkSize is the recipient count per bulk INSERT.
// PostgREST accepts a JSON array as the body of a single INSERT, so a
// full 5000-candidate run becomes ~10 requests of 500 rather than 5000
// serialized single-row POSTs. 500 keeps each request body small.
const digestEnqueueChunkSize = 500

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
// Returns the number of jobs enqueued. The recipients are bulk-inserted
// in chunks of digestEnqueueChunkSize; a chunk that fails to enqueue is
// logged and skipped rather than aborting the whole run — one bad chunk
// shouldn't strand every other recipient's digest.
func EnqueueAllWeeklyDigests(ctx context.Context, be DigestBuilderBackend, log *slog.Logger) (int, error) {
	candidates, err := be.FetchDigestCandidates(ctx, maxDigestCandidatesPerRun)
	if err != nil {
		return 0, err
	}
	enqueued := 0
	for start := 0; start < len(candidates); start += digestEnqueueChunkSize {
		end := start + digestEnqueueChunkSize
		if end > len(candidates) {
			end = len(candidates)
		}
		chunk := candidates[start:end]
		if err := be.EnqueueWeeklyDigests(ctx, chunk); err != nil {
			if log != nil {
				log.Warn("weekly_digest builder: chunk enqueue failed; skipping chunk",
					"chunk_start", start, "chunk_size", len(chunk), "err", err)
			}
			continue
		}
		enqueued += len(chunk)
	}
	if log != nil {
		log.Info("weekly_digest builder: enqueued jobs", "candidates", len(candidates), "enqueued", enqueued)
	}
	return enqueued, nil
}
