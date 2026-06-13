package internal

import (
	"context"
	"errors"
	"log/slog"
	"strconv"
	"testing"
)

type fakeDigestBuilderBackend struct {
	candidates    []string
	candidatesErr error
	enqueued      []string
	chunkSizes    []int            // one entry per EnqueueWeeklyDigests call
	enqueueErrFor map[string]error // a chunk containing this user errors as a whole
}

func (f *fakeDigestBuilderBackend) FetchDigestCandidates(_ context.Context, _ int) ([]string, error) {
	if f.candidatesErr != nil {
		return nil, f.candidatesErr
	}
	return f.candidates, nil
}

func (f *fakeDigestBuilderBackend) EnqueueWeeklyDigests(_ context.Context, userIDs []string) error {
	f.chunkSizes = append(f.chunkSizes, len(userIDs))
	for _, uid := range userIDs {
		if err, ok := f.enqueueErrFor[uid]; ok {
			return err
		}
	}
	f.enqueued = append(f.enqueued, userIDs...)
	return nil
}

func nullLog() *slog.Logger { return slog.New(slog.NewTextHandler(nullWriter{}, nil)) }

func TestEnqueueAllWeeklyDigests_EnqueuesEveryCandidate(t *testing.T) {
	be := &fakeDigestBuilderBackend{candidates: []string{"u1", "u2", "u3"}}
	n, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog())
	if err != nil {
		t.Fatalf("builder: %v", err)
	}
	if n != 3 {
		t.Errorf("want 3 enqueued, got %d", n)
	}
	if len(be.enqueued) != 3 {
		t.Errorf("want 3 jobs recorded, got %v", be.enqueued)
	}
}

func TestEnqueueAllWeeklyDigests_NoCandidatesIsNoop(t *testing.T) {
	be := &fakeDigestBuilderBackend{candidates: nil}
	n, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog())
	if err != nil {
		t.Fatalf("builder: %v", err)
	}
	if n != 0 || len(be.enqueued) != 0 {
		t.Errorf("no candidates → no enqueue; got n=%d enqueued=%v", n, be.enqueued)
	}
}

func TestEnqueueAllWeeklyDigests_SelectErrorBubbles(t *testing.T) {
	be := &fakeDigestBuilderBackend{candidatesErr: errors.New("db down")}
	if _, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog()); err == nil {
		t.Fatal("a candidate-select failure must bubble (the whole run can't proceed)")
	}
}

func TestEnqueueAllWeeklyDigests_ChunksBulkInserts(t *testing.T) {
	// 1100 candidates with a 500 chunk size → 3 bulk inserts (500/500/100).
	const n = 1100
	cands := make([]string, n)
	for i := range cands {
		cands[i] = "u" + strconv.Itoa(i)
	}
	be := &fakeDigestBuilderBackend{candidates: cands}
	got, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog())
	if err != nil {
		t.Fatalf("builder: %v", err)
	}
	if got != n {
		t.Errorf("want %d enqueued, got %d", n, got)
	}
	wantCalls := (n + digestEnqueueChunkSize - 1) / digestEnqueueChunkSize
	if len(be.chunkSizes) != wantCalls {
		t.Errorf("want %d bulk-insert calls (ceil(%d/%d)), got %d: %v",
			wantCalls, n, digestEnqueueChunkSize, len(be.chunkSizes), be.chunkSizes)
	}
	want := []int{digestEnqueueChunkSize, digestEnqueueChunkSize, n - 2*digestEnqueueChunkSize}
	if len(be.chunkSizes) != len(want) {
		t.Fatalf("chunk-size shape mismatch: got %v want %v", be.chunkSizes, want)
	}
	for i, w := range want {
		if be.chunkSizes[i] != w {
			t.Errorf("chunk %d: got %d, want %d (all chunks: %v)", i, be.chunkSizes[i], w, be.chunkSizes)
		}
	}
	if len(be.enqueued) != n {
		t.Errorf("want %d recipients recorded, got %d", n, len(be.enqueued))
	}
}

func TestEnqueueAllWeeklyDigests_FailingChunkSkipsNotAborts(t *testing.T) {
	// 1100 candidates → chunks [0,500) [500,1000) [1000,1100). Fail the
	// middle chunk; the first and last must still enqueue.
	const n = 1100
	cands := make([]string, n)
	for i := range cands {
		cands[i] = "u" + strconv.Itoa(i)
	}
	be := &fakeDigestBuilderBackend{
		candidates:    cands,
		enqueueErrFor: map[string]error{"u600": errors.New("transient")}, // in the second chunk
	}
	got, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog())
	if err != nil {
		t.Fatalf("one bad chunk must not fail the whole run: %v", err)
	}
	// First chunk (500) + last chunk (100) succeed; middle (500) is skipped.
	wantEnqueued := digestEnqueueChunkSize + (n - 2*digestEnqueueChunkSize)
	if got != wantEnqueued {
		t.Errorf("want %d enqueued (first + last chunk), got %d", wantEnqueued, got)
	}
	// All three chunks were attempted even though the middle failed.
	if len(be.chunkSizes) != 3 {
		t.Errorf("want 3 chunk attempts, got %d: %v", len(be.chunkSizes), be.chunkSizes)
	}
	if len(be.enqueued) != wantEnqueued {
		t.Errorf("want %d recipients recorded, got %d", wantEnqueued, len(be.enqueued))
	}
}
