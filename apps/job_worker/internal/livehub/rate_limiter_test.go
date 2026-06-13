package livehub

import (
	"testing"
	"time"
)

func TestPushRateLimiter_ReapDropsIdleBucketsKeepsFresh(t *testing.T) {
	p := newPushRateLimiter(12, time.Minute)
	p.allow("fresh")
	p.allow("idle")

	// Backdate the idle bucket's last refill well past maxIdle.
	v, ok := p.buckets.Load("idle")
	if !ok {
		t.Fatal("idle bucket should exist after allow()")
	}
	b := v.(*roomBucket)
	b.mu.Lock()
	b.lastFill = time.Now().Add(-2 * time.Hour)
	b.mu.Unlock()

	dropped := p.reap(time.Now(), time.Hour)
	if dropped != 1 {
		t.Fatalf("expected exactly 1 idle bucket reaped, got %d", dropped)
	}
	if _, ok := p.buckets.Load("idle"); ok {
		t.Fatal("idle bucket must be reaped (the leak this fixes)")
	}
	if _, ok := p.buckets.Load("fresh"); !ok {
		t.Fatal("a recently-active bucket must be kept")
	}
}
