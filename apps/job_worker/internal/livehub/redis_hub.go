package livehub

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// RedisHub is the multi-replica variant of [Hub]: Publish + Subscribe
// go through Redis pub/sub, and the last-known ping survives across
// process restarts via a per-run TTL'd key. Drop-in for the
// in-process [Hub] — both satisfy [LivePubSub] — so `Server` and
// `JWTAuthorizer` don't change shape.
//
// Storage model:
//
//   - `live:{runID}:ch`    — pub/sub channel; every push PUBLISHes
//     here. Spectators on any replica SUBSCRIBE.
//   - `live:{runID}:last`  — last-known ping (JSON), EXPIREs after
//     `LastKnownTTL` (default 24 h). Mirrors the in-process Hub's
//     "keep one ping after the room GCs so a refresh sees the
//     runner" behaviour; with Redis the spectator can also be on a
//     different process than the publisher.
//
// Per-room caches (zones + run-meta) stay in-memory on each process.
// They're not load-bearing across replicas — a second process that
// hits the same run does its own Supabase round-trip on first
// touch, which is fine because zones rarely change mid-run and the
// run-meta lookup is one row per active publisher.
//
// Subscriber buffer (`subBufferSize`, currently 8) is the same as
// the in-process Hub for the same reason: ~40s of slack at the
// 5 s broadcaster throttle, bounded so a stuck spectator can't
// grow memory unbounded.
type RedisHub struct {
	rdb *redis.Client
	// LastKnownTTL is how long the per-run `:last` key sticks
	// around. Zero → default 24 h. Matches the roadmap's per-run
	// 24h TTL line.
	LastKnownTTL time.Duration
	// KeyPrefix lets multiple environments share a Redis instance
	// without colliding. Zero → "live:".
	KeyPrefix string
	Log       *slog.Logger

	// Per-process room cache for zones + run-meta. Same shape as
	// the in-process Hub's room struct (without the subscribers
	// map — Redis owns that fan-out now).
	roomsMu sync.Mutex
	rooms   map[string]*redisRoom
}

type redisRoom struct {
	mu sync.Mutex
	// `zonesAt` / `runMetaAt` record the last successful fetch so both
	// caches refresh every CacheRefreshTTL — same privacy contract as
	// the in-process Hub. A non-zero timestamp with nil zones / nil
	// runMeta means "fetched, and there genuinely are none / the run
	// doesn't exist", which is distinct from "never fetched".
	zonesAt   time.Time
	zones     []PrivacyZone
	runMetaAt time.Time
	runMeta   *RunMeta
}

// NewRedisHub builds a hub backed by an existing redis.Client. The
// caller owns the client (ping/close); the hub is just a thin
// adapter so test code can wire miniredis without booting a real
// server.
func NewRedisHub(rdb *redis.Client) *RedisHub {
	return &RedisHub{rdb: rdb, rooms: make(map[string]*redisRoom)}
}

func (h *RedisHub) ttl() time.Duration {
	if h.LastKnownTTL > 0 {
		return h.LastKnownTTL
	}
	return 24 * time.Hour
}

func (h *RedisHub) prefix() string {
	if h.KeyPrefix != "" {
		return h.KeyPrefix
	}
	return "live:"
}

func (h *RedisHub) chanKey(runID string) string { return h.prefix() + runID + ":ch" }
func (h *RedisHub) lastKey(runID string) string { return h.prefix() + runID + ":last" }
func (h *RedisHub) histKey(runID string) string { return h.prefix() + runID + ":hist" }

// Publish PUBLISHes the ping on the per-run channel and updates the
// last-known key with TTL. Returns the receiver count Redis reports
// — i.e. the number of pub/sub consumers that received the message
// at this moment in time. A buffer-full pubsub subscriber is dropped
// by Redis transparently; the count here is "successful deliveries".
func (h *RedisHub) Publish(runID string, p Ping) int {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	payload, err := json.Marshal(p)
	if err != nil {
		h.log().Warn("redis_hub: marshal failed", "err", err, "run_id", runID)
		return 0
	}
	// Update last-known first so a spectator that connects between
	// the publish and a delayed pubsub receive can still see the
	// runner via the snapshot path. Best-effort — log on failure
	// but don't abort the publish.
	if err := h.rdb.Set(ctx, h.lastKey(runID), payload, h.ttl()).Err(); err != nil {
		h.log().Warn("redis_hub: last-known set failed", "err", err, "run_id", runID)
	}
	// Append to the history list + trim to HistoryRingSize. Same TTL
	// as lastKey. Persona-hunt Round 3 finding Ultra #1 — late-
	// joining spectators can replay the recent track.
	pipe := h.rdb.Pipeline()
	pipe.RPush(ctx, h.histKey(runID), payload)
	pipe.LTrim(ctx, h.histKey(runID), -HistoryRingSize, -1)
	pipe.Expire(ctx, h.histKey(runID), h.ttl())
	if _, err := pipe.Exec(ctx); err != nil {
		h.log().Warn("redis_hub: history append failed", "err", err, "run_id", runID)
	}
	recvCount, err := h.rdb.Publish(ctx, h.chanKey(runID), payload).Result()
	if err != nil {
		h.log().Warn("redis_hub: publish failed", "err", err, "run_id", runID)
		return 0
	}
	return int(recvCount)
}

// Subscribe opens a per-call Redis pub/sub. The returned channel is
// owned by the caller; unsub closes the pubsub + the channel. On
// subscribe the caller is pre-loaded with the last-known ping from
// the `:last` key if one is present (matches the in-process Hub's
// late-joiner behaviour).
func (h *RedisHub) Subscribe(ctx context.Context, runID string) (<-chan Ping, func(), error) {
	return h.subscribe(ctx, runID, true)
}

// SubscribeNoReplay is identical to Subscribe but skips the
// `:last` key preload. See the in-process Hub.SubscribeNoReplay for
// the rationale (privacy-zone re-eval at request time).
// Persona-hunt finding Pro-Round2 #1.
func (h *RedisHub) SubscribeNoReplay(ctx context.Context, runID string) (<-chan Ping, func(), error) {
	return h.subscribe(ctx, runID, false)
}

func (h *RedisHub) subscribe(ctx context.Context, runID string, replay bool) (<-chan Ping, func(), error) {
	pubsub := h.rdb.Subscribe(ctx, h.chanKey(runID))
	out := make(chan Ping, subBufferSize)

	// Pre-load last-known if present (unless caller opted out).
	if replay {
		if last := h.LastKnown(runID); last != nil {
			out <- *last
		}
	}

	closeOnce := &sync.Once{}
	closeFn := func() {
		closeOnce.Do(func() {
			_ = pubsub.Close()
			close(out)
		})
	}

	// Cancel-driven cleanup: if the caller's context is cancelled
	// before they call unsub explicitly we still close cleanly. The
	// caller SHOULD always call unsub via defer; this is a safety net.
	if ctx != nil && ctx.Done() != nil {
		go func() {
			<-ctx.Done()
			closeFn()
		}()
	}

	// Receive loop on a goroutine — forwards every Redis message
	// onto `out`. A buffer-full `out` drops the ping (same trySend
	// semantics as the in-process Hub).
	go func() {
		ch := pubsub.Channel()
		for msg := range ch {
			var p Ping
			if err := json.Unmarshal([]byte(msg.Payload), &p); err != nil {
				h.log().Debug("redis_hub: bad payload, skipping", "err", err)
				continue
			}
			select {
			case out <- p:
			default:
				// Buffer full — drop. The spectator misses one
				// ping; the next one (≤5 s) arrives normally.
			}
		}
	}()

	return out, closeFn, nil
}

// LastKnown reads the `:last` key. Returns nil when there is no
// stored value (key missing or expired) — matches the in-process
// Hub contract.
func (h *RedisHub) LastKnown(runID string) *Ping {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	raw, err := h.rdb.Get(ctx, h.lastKey(runID)).Result()
	if errors.Is(err, redis.Nil) {
		return nil
	}
	if err != nil {
		h.log().Warn("redis_hub: last-known get failed", "err", err, "run_id", runID)
		return nil
	}
	var p Ping
	if err := json.Unmarshal([]byte(raw), &p); err != nil {
		h.log().Warn("redis_hub: last-known decode failed", "err", err, "run_id", runID)
		return nil
	}
	return &p
}

// History reads up to [max] most-recent pings from the `:hist` list
// (LPUSH-style appends with LTRIM to HistoryRingSize). Returned in
// chronological order (oldest first). Persona-hunt Round 3 #U1.
func (h *RedisHub) History(runID string, max int) []Ping {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if max <= 0 || max > HistoryRingSize {
		max = HistoryRingSize
	}
	raws, err := h.rdb.LRange(ctx, h.histKey(runID), int64(-max), -1).Result()
	if errors.Is(err, redis.Nil) {
		return nil
	}
	if err != nil {
		h.log().Warn("redis_hub: history range failed", "err", err, "run_id", runID)
		return nil
	}
	out := make([]Ping, 0, len(raws))
	for _, raw := range raws {
		var p Ping
		if err := json.Unmarshal([]byte(raw), &p); err != nil {
			h.log().Warn("redis_hub: history decode skipped", "err", err, "run_id", runID)
			continue
		}
		out = append(out, p)
	}
	return out
}

// LoadZones lazily fetches + caches privacy zones for `runID`, refreshing
// every CacheRefreshTTL. Same API + semantics as the in-process Hub: a
// mid-run privacy-zone change starts being honoured within the TTL. The
// cache is per-process — each replica serving the publisher fetches on
// its own TTL.
func (h *RedisHub) LoadZones(ctx context.Context, runID string, fetcher ZoneFetcher) ([]PrivacyZone, error) {
	r := h.roomFor(runID)
	r.mu.Lock()
	if !r.zonesAt.IsZero() && time.Since(r.zonesAt) < CacheRefreshTTL() {
		out := append([]PrivacyZone(nil), r.zones...)
		r.mu.Unlock()
		return out, nil
	}
	r.mu.Unlock()

	zones, err := fetcher.Zones(ctx, runID)
	if err != nil {
		return nil, err
	}
	r.mu.Lock()
	r.zonesAt = time.Now()
	r.zones = zones
	out := append([]PrivacyZone(nil), r.zones...)
	r.mu.Unlock()
	return out, nil
}

// LoadRunMeta lazily fetches + caches run metadata for `runID`,
// refreshing every CacheRefreshTTL. Same API + semantics as the
// in-process Hub: a mid-run `is_public = false` flip stops serving anon
// spectators within the TTL — without the refresh the cached
// `is_public: true` would live for the room's lifetime and leak a
// now-private run's live location indefinitely. A nil result + nil error
// after a successful fetch means "the run row doesn't exist" — the
// JWTAuthorizer treats that as deny.
func (h *RedisHub) LoadRunMeta(ctx context.Context, runID string, fetcher RunMetaFetcher) (*RunMeta, error) {
	r := h.roomFor(runID)
	r.mu.Lock()
	if !r.runMetaAt.IsZero() && time.Since(r.runMetaAt) < CacheRefreshTTL() {
		meta := r.runMeta
		r.mu.Unlock()
		return meta, nil
	}
	r.mu.Unlock()

	meta, err := fetcher.RunMeta(ctx, runID)
	if err != nil {
		return nil, err
	}
	r.mu.Lock()
	r.runMetaAt = time.Now()
	r.runMeta = meta
	out := r.runMeta
	r.mu.Unlock()
	return out, nil
}

func (h *RedisHub) roomFor(runID string) *redisRoom {
	h.roomsMu.Lock()
	defer h.roomsMu.Unlock()
	r, ok := h.rooms[runID]
	if !ok {
		r = &redisRoom{}
		h.rooms[runID] = r
	}
	return r
}

func (h *RedisHub) log() *slog.Logger {
	if h.Log != nil {
		return h.Log
	}
	return slog.Default()
}

// Compile-time check that RedisHub satisfies LivePubSub.
var _ LivePubSub = (*RedisHub)(nil)

// ConfigureRedis builds a *redis.Client from a connection URL. The
// URL shape is the standard `redis://[user:pass@]host:port[/db]` or
// `rediss://...` for TLS. Returns an error if the URL doesn't parse;
// the caller (main.go) treats that as "fall back to in-process Hub".
//
// Kept here rather than main.go so the same URL parsing applies in
// tests that want a real-ish Redis client without booting miniredis.
func ConfigureRedis(url string) (*redis.Client, error) {
	if url == "" {
		return nil, fmt.Errorf("redis: empty url")
	}
	opts, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("redis: parse url: %w", err)
	}
	return redis.NewClient(opts), nil
}
