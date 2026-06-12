package internal

import (
	"context"
	"errors"
	"log/slog"
	"testing"
)

type fakeDigestBuilderBackend struct {
	candidates    []string
	candidatesErr error
	enqueued      []string
	enqueueErrFor map[string]error // per-user enqueue error injection
}

func (f *fakeDigestBuilderBackend) FetchDigestCandidates(_ context.Context, _ int) ([]string, error) {
	if f.candidatesErr != nil {
		return nil, f.candidatesErr
	}
	return f.candidates, nil
}

func (f *fakeDigestBuilderBackend) EnqueueWeeklyDigest(_ context.Context, userID string) error {
	if err, ok := f.enqueueErrFor[userID]; ok {
		return err
	}
	f.enqueued = append(f.enqueued, userID)
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

func TestEnqueueAllWeeklyDigests_PerRecipientErrorSkipsNotAborts(t *testing.T) {
	be := &fakeDigestBuilderBackend{
		candidates:    []string{"u1", "u2", "u3"},
		enqueueErrFor: map[string]error{"u2": errors.New("transient")},
	}
	n, err := EnqueueAllWeeklyDigests(context.Background(), be, nullLog())
	if err != nil {
		t.Fatalf("one bad recipient must not fail the whole run: %v", err)
	}
	if n != 2 {
		t.Errorf("want 2 enqueued (u1, u3), got %d", n)
	}
	if len(be.enqueued) != 2 || be.enqueued[0] != "u1" || be.enqueued[1] != "u3" {
		t.Errorf("expected u1+u3 enqueued, got %v", be.enqueued)
	}
}
