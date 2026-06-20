package main

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/smtp"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/Absence0760/project-running/apps/job_worker/internal"
	"github.com/Absence0760/project-running/apps/job_worker/internal/bouncehook"
	"github.com/Absence0760/project-running/apps/job_worker/internal/dataexport"
	"github.com/Absence0760/project-running/apps/job_worker/internal/livehub"
	"github.com/Absence0760/project-running/apps/job_worker/internal/nativepush"
	"github.com/Absence0760/project-running/apps/job_worker/internal/premium"
	"github.com/Absence0760/project-running/apps/job_worker/internal/stravahook"
	"github.com/Absence0760/project-running/apps/job_worker/internal/unsubscribe"
	"github.com/Absence0760/project-running/apps/job_worker/internal/webpush"
)

// stravaJobEnqueuer adapts SupabaseClient.EnqueueStravaEvent to the
// stravahook.JobEnqueuer interface. The leaf-package stravahook
// declares its own payload struct so its tests stay isolated from
// the `internal` package; we translate across them by marshalling
// to the wire-identical map[string]any here.
type stravaJobEnqueuer struct {
	client *internal.SupabaseClient
}

func (e *stravaJobEnqueuer) EnqueueStravaEvent(ctx context.Context, p stravahook.StravaEventPayload) (int64, error) {
	return e.client.EnqueueStravaEvent(ctx, map[string]any{
		"object_type": p.ObjectType,
		"object_id":   p.ObjectID,
		"aspect_type": p.AspectType,
		"owner_id":    p.OwnerID,
		"event_time":  p.EventTime,
	})
}

// dataexportBackend adapts SupabaseClient to dataexport.Backend.
// Same reasoning as stravaJobEnqueuer — the leaf package keeps its
// own types so tests don't import `internal`; this adapter is the
// production translation layer.
type dataexportBackend struct {
	client *internal.SupabaseClient
}

func (b *dataexportBackend) CheckRateLimitTiered(ctx context.Context, userID, bucket string, freeMax, proMax, windowSec int) (bool, int, error) {
	return b.client.CheckRateLimitTiered(ctx, userID, bucket, freeMax, proMax, windowSec)
}

func (b *dataexportBackend) FetchExportRuns(ctx context.Context, userID string, limit int) ([]dataexport.ExportRun, error) {
	rows, err := b.client.FetchExportRuns(ctx, userID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]dataexport.ExportRun, len(rows))
	for i, r := range rows {
		out[i] = dataexport.ExportRun{
			ID: r.ID, UserID: r.UserID, StartedAt: r.StartedAt,
			DurationS: r.DurationS, DistanceM: r.DistanceM,
			Source: r.Source, ActivityType: r.ActivityType, IsDNF: r.IsDNF,
			ExternalID: r.ExternalID,
			Metadata:   r.Metadata, TrackURL: r.TrackURL, HrSeriesURL: r.HrSeriesURL,
			IsPublic: r.IsPublic, EventID: r.EventID, RouteID: r.RouteID,
			CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
	}
	return out, nil
}

func (b *dataexportBackend) DownloadTrackBytes(ctx context.Context, path string) ([]dataexport.TrackPoint, error) {
	pts, err := b.client.DownloadTrack(ctx, path)
	if err != nil {
		return nil, nil // swallow; caller drops the per-run GPX file
	}
	out := make([]dataexport.TrackPoint, len(pts))
	for i, p := range pts {
		out[i] = dataexport.TrackPoint{Lat: p.Lat, Lng: p.Lng}
		if p.Elevation != nil {
			ele := *p.Elevation
			out[i].Ele = &ele
		}
		if p.Timestamp != nil {
			ts := p.Timestamp.Format(time.RFC3339)
			out[i].Ts = &ts
		}
		if p.Bpm != nil {
			b := *p.Bpm
			out[i].Bpm = &b
		}
	}
	return out, nil
}

func (b *dataexportBackend) FetchExportRoutes(ctx context.Context, userID string) ([]dataexport.ExportRoute, error) {
	rows, err := b.client.FetchExportRoutes(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]dataexport.ExportRoute, len(rows))
	for i, r := range rows {
		out[i] = dataexport.ExportRoute{
			ID: r.ID, Name: r.Name, Waypoints: r.Waypoints,
			DistanceM: r.DistanceM, ElevationM: r.ElevationM,
			Surface: r.Surface, IsPublic: r.IsPublic, Slug: r.Slug,
			Tags: r.Tags, Featured: r.Featured, RunCount: r.RunCount,
			IsStarred: r.IsStarred, Description: r.Description,
			ClubID: r.ClubID, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
		}
	}
	return out, nil
}

func (b *dataexportBackend) FetchExportProfile(ctx context.Context, userID string) (map[string]interface{}, error) {
	return b.client.FetchExportProfile(ctx, userID)
}

func (b *dataexportBackend) FetchUserSettingsPrefs(ctx context.Context, userID string) (map[string]interface{}, error) {
	return b.client.FetchUserSettingsPrefs(ctx, userID)
}

func (b *dataexportBackend) DownloadRawTrackBytes(ctx context.Context, path string) ([]byte, error) {
	return b.client.DownloadRawTrackBytes(ctx, path)
}

func (b *dataexportBackend) DownloadPhoto(ctx context.Context, path string) ([]byte, string, error) {
	return b.client.DownloadPhoto(ctx, path)
}

func (b *dataexportBackend) FetchExportPersonalDataTables(ctx context.Context, userID string) (map[string][]map[string]interface{}, error) {
	return b.client.FetchExportPersonalDataTables(ctx, userID)
}

func (b *dataexportBackend) UploadExportArtifact(ctx context.Context, path, contentType string, body []byte) error {
	return b.client.UploadExportArtifact(ctx, path, contentType, body)
}

func (b *dataexportBackend) CreateSignedURL(ctx context.Context, path string, ttlSec int) (string, error) {
	return b.client.CreateSignedURL(ctx, path, ttlSec)
}

// premiumBackend adapts SupabaseClient to premium.Backend.
type premiumBackend struct {
	client *internal.SupabaseClient
}

func (b *premiumBackend) FetchUserSubscriptionTier(ctx context.Context, userID string) (string, error) {
	return b.client.FetchUserSubscriptionTier(ctx, userID)
}

// unsubscribeBackend adapts SupabaseClient to unsubscribe.Backend. Same
// leaf-package reasoning as the others.
type unsubscribeBackend struct {
	client *internal.SupabaseClient
}

func (b *unsubscribeBackend) SetWeeklyDigestPrefOff(ctx context.Context, userID string) error {
	return b.client.SetWeeklyDigestPrefOff(ctx, userID)
}

func (b *unsubscribeBackend) InsertEmailSuppression(ctx context.Context, email, reason string) error {
	return b.client.InsertEmailSuppression(ctx, email, reason)
}

func (b *unsubscribeBackend) FetchUserEmail(ctx context.Context, userID string) (string, error) {
	return b.client.FetchUserEmail(ctx, userID)
}

func (b *premiumBackend) FetchPremiumRuns(ctx context.Context, userID string, since time.Time, limit int) ([]premium.PremiumRun, error) {
	rows, err := b.client.FetchPremiumRuns(ctx, userID, since, limit)
	if err != nil {
		return nil, err
	}
	out := make([]premium.PremiumRun, len(rows))
	for i, r := range rows {
		out[i] = premium.PremiumRun{
			StartedAt:    r.StartedAt,
			DistanceM:    r.DistanceM,
			DurationS:    r.DurationS,
			ActivityType: r.ActivityType,
			Metadata:     r.Metadata,
		}
	}
	return out, nil
}

// main wires environment → SupabaseClient → Worker.Run. Kept thin so
// the worker logic can be exercised from tests against a mock backend
// without booting an HTTP transport.
// loadEnvFiles reads simple KEY=VALUE .env files in order and sets any
// variable NOT already present in the process environment. Mirrors
// godotenv.Load semantics — the existing env wins, and an earlier file
// in the list wins over a later one — but stays stdlib-only: the
// module pins a Go toolchain the build host may not have, so adding a
// dependency (and a go.sum entry) for ~20 lines isn't worth it.
//
// Repo-wide convention (decisions §137): .env.local (gitignored, your
// real secrets) overrides .env.development (committed, non-secret local
// defaults). In production the multi-stage Docker image ships only the
// compiled binary — neither file is present — so this is a no-op and
// Fly secrets are the sole source. The "existing env wins" rule is a
// second guard against a stray committed default reaching prod.
func loadEnvFiles(paths ...string) {
	for _, path := range paths {
		f, err := os.Open(path)
		if err != nil {
			continue // missing file is fine (prod, or no local override)
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			key, val, ok := strings.Cut(line, "=")
			if !ok {
				continue
			}
			key = strings.TrimSpace(key)
			val = strings.TrimSpace(val)
			// Strip one layer of matching surrounding quotes.
			if len(val) >= 2 && (val[0] == '"' || val[0] == '\'') && val[len(val)-1] == val[0] {
				val = val[1 : len(val)-1]
			}
			if key == "" {
				continue
			}
			if _, present := os.LookupEnv(key); present {
				continue // shell / Fly env (and earlier files) take precedence
			}
			_ = os.Setenv(key, val)
		}
		f.Close()
	}
}

func main() {
	loadEnvFiles(".env.local", ".env.development")

	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	baseURL := requireEnv(logger, "SUPABASE_URL")
	serviceKey := requireEnv(logger, "SUPABASE_SERVICE_ROLE_KEY")
	workerID := os.Getenv("WORKER_ID")
	if workerID == "" {
		host, _ := os.Hostname()
		if host == "" {
			host = "worker"
		}
		workerID = host
	}

	// OSRM_URL is the dev / prod hook that swaps the passthrough
	// shim for the real /match-based engine. Empty → passthrough,
	// which is enough for end-to-end smoke tests of the rest of the
	// pipeline. See apps/job_worker/osrm/README.md for the local
	// stack.
	var matcher internal.Matcher = internal.PassthroughMatcher{}
	if osrmURL := os.Getenv("OSRM_URL"); osrmURL != "" {
		matcher = internal.NewOSRMMatcher(osrmURL)
		logger.Info("matcher selected", "engine", "osrm", "url", osrmURL)
	} else {
		logger.Info("matcher selected", "engine", "passthrough")
	}

	client := internal.NewSupabaseClient(baseURL, serviceKey)

	// Strava OAuth client for the token_refresh dispatch path.
	// Optional — when either env var is missing the worker still
	// drains map_match jobs, but any token_refresh row fails permanent
	// with a clear "Strava client not configured" message. The Edge
	// Function path remains the fallback during cutover.
	stravaID := os.Getenv("STRAVA_CLIENT_ID")
	stravaSecret := os.Getenv("STRAVA_CLIENT_SECRET")
	var strava internal.StravaIngestor
	if stravaID != "" && stravaSecret != "" {
		strava = &internal.StravaClient{
			ClientID:     stravaID,
			ClientSecret: stravaSecret,
			HTTP:         client.HTTP, // reuse pooled client
		}
		logger.Info("strava: enabled (token_refresh + strava_event dispatch armed)")
	} else {
		logger.Warn("strava: DISABLED — STRAVA_CLIENT_ID/SECRET unset; token_refresh + strava_event jobs will fail permanent")
	}

	// Email sender for kind='notification_email' jobs. Optional — when
	// SMTP_HOST is unset the worker still drains every other kind, and
	// notification_email jobs finish done while leaving the rows pending
	// (so a later email-enabled deploy can send them). Local dev points
	// at the Supabase Mailpit catcher: SMTP_HOST=127.0.0.1 SMTP_PORT=54325,
	// no auth, inspect at http://127.0.0.1:54324. Production sets a real
	// provider (Resend / SES SMTP) with SMTP_USERNAME + SMTP_PASSWORD.
	var emailSender internal.EmailSender
	if smtpHost := os.Getenv("SMTP_HOST"); smtpHost != "" {
		smtpPort := os.Getenv("SMTP_PORT")
		if smtpPort == "" {
			smtpPort = "587"
		}
		from := os.Getenv("SMTP_FROM")
		if from == "" {
			from = "Threkir <noreply@threkir.com>"
		}
		var auth smtp.Auth
		if user := os.Getenv("SMTP_USERNAME"); user != "" {
			auth = smtp.PlainAuth("", user, os.Getenv("SMTP_PASSWORD"), smtpHost)
		}
		emailSender = &internal.SMTPSender{
			Addr: smtpHost + ":" + smtpPort,
			From: from,
			Auth: auth,
		}
		logger.Info("notification_email: enabled", "smtp", smtpHost+":"+smtpPort, "auth", auth != nil)
	} else {
		logger.Warn("notification_email: DISABLED — SMTP_HOST unset; notification_email jobs finish without sending")
	}
	appBaseURL := os.Getenv("APP_BASE_URL")
	if appBaseURL == "" {
		appBaseURL = "https://threkir.com"
	}

	// Web-push sender for kind='web_push' jobs. Optional — when the VAPID
	// keypair is unset the worker still drains every other kind, and web_push
	// jobs finish done while leaving the rows pending (so a later push-enabled
	// deploy can send them). VAPID_PUBLIC_KEY is the same key the browser
	// subscribed with (apps/web's PUBLIC_VAPID_PUBLIC_KEY); VAPID_PRIVATE_KEY
	// is the operator-generated private half; VAPID_SUBJECT is the `mailto:` /
	// origin contact the spec requires (defaults to a mailto on APP_BASE_URL).
	var webPushSender internal.WebPushSender
	if vapidPub := os.Getenv("VAPID_PUBLIC_KEY"); vapidPub != "" {
		if vapidPriv := os.Getenv("VAPID_PRIVATE_KEY"); vapidPriv != "" {
			subject := os.Getenv("VAPID_SUBJECT")
			if subject == "" {
				subject = "mailto:ops@threkir.com"
			}
			sender, err := webpush.NewSender(subject, vapidPub, vapidPriv, client.HTTP)
			if err != nil {
				// A bad keypair is a deploy misconfiguration — fail loudly
				// rather than silently dropping every push.
				logger.Error("web_push: invalid VAPID configuration — refusing to start", "err", err)
				os.Exit(2)
			}
			webPushSender = sender
			logger.Info("web_push: enabled", "subject", subject)
		} else {
			logger.Warn("web_push: DISABLED — VAPID_PUBLIC_KEY set but VAPID_PRIVATE_KEY unset; web_push jobs finish without sending")
		}
	} else {
		logger.Warn("web_push: DISABLED — VAPID_PUBLIC_KEY unset; web_push jobs finish without sending")
	}

	// Native-push sender for kind='native_push' jobs (FCM HTTP v1 for Android,
	// APNs HTTP/2 for iOS). Optional + fail-closed — when neither transport is
	// credentialed the worker still drains every other kind, and native_push
	// jobs finish done while leaving the rows pending (so a later credentialed
	// deploy delivers the backlog). FCM needs FCM_SERVICE_ACCOUNT_JSON +
	// FCM_PROJECT_ID; APNs needs APNS_KEY_P8 + APNS_KEY_ID + APNS_TEAM_ID +
	// APNS_TOPIC (+ optional APNS_SANDBOX=1). Either group alone enables that
	// platform; an invalid credential fails the worker at startup (exit 2).
	var nativePushSender internal.NativePushSender
	nativeCfg := nativepush.Config{
		FCMServiceAccountJSON: []byte(os.Getenv("FCM_SERVICE_ACCOUNT_JSON")),
		FCMProjectID:          os.Getenv("FCM_PROJECT_ID"),
		APNSKeyP8:             []byte(os.Getenv("APNS_KEY_P8")),
		APNSKeyID:             os.Getenv("APNS_KEY_ID"),
		APNSTeamID:            os.Getenv("APNS_TEAM_ID"),
		APNSTopic:             os.Getenv("APNS_TOPIC"),
		APNSSandbox:           os.Getenv("APNS_SANDBOX") == "1",
	}
	if sender, err := nativepush.NewSender(nativeCfg, client.HTTP); err != nil {
		// A configured-but-invalid credential is a deploy misconfiguration —
		// fail loudly rather than silently dropping every native push.
		logger.Error("native_push: invalid FCM/APNs configuration — refusing to start", "err", err)
		os.Exit(2)
	} else if sender != nil {
		nativePushSender = sender
		logger.Info("native_push: enabled",
			"fcm", nativeCfg.FCMProjectID != "",
			"apns", len(nativeCfg.APNSKeyP8) > 0)
	} else {
		logger.Warn("native_push: DISABLED — no FCM/APNs credentials set; native_push jobs finish without sending")
	}

	// `lastClaimAt` is the heartbeat the /health endpoint reads. The
	// worker's poll loop bumps it on every successful poll
	// (claim-or-empty), so /health flips to 503 only when the loop
	// itself is stuck — distinct from "queue empty" (which is fine).
	// Initialise to start-time so a freshly-launched container reports
	// healthy until the first poll lands.
	var lastClaimAtUnix atomic.Int64
	lastClaimAtUnix.Store(time.Now().Unix())

	// Weekly-digest unsubscribe secret. Keys the stateless RFC 8058
	// unsubscribe HMAC the digest handler mints + the unsubscribe endpoint
	// verifies. Optional — unset → the digest renders WITHOUT a
	// List-Unsubscribe header/link and the endpoint 503s (the consistent
	// fail-closed posture). NOTE: this only gates the unsubscribe plumbing;
	// the digest SEND itself is gated by no scheduled builder existing —
	// enabling that is a separate CISO/counsel step (decisions / email.md).
	digestUnsubSecret := os.Getenv("WEEKLY_DIGEST_UNSUB_SECRET")

	worker := &internal.Worker{
		Backend:           client,
		Matcher:           matcher,
		Strava:            strava,
		Email:             emailSender,
		WebPush:           webPushSender,
		NativePush:        nativePushSender,
		AppBaseURL:        appBaseURL,
		DigestUnsubSecret: digestUnsubSecret,
		Config: internal.Config{
			WorkerID:       workerID,
			PollInterval:   2 * time.Second,
			HandleTimeout:  5 * time.Minute,
			TransientDelay: 30,
		},
		Log:        logger,
		OnPollTick: func() { lastClaimAtUnix.Store(time.Now().Unix()) },
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Start a tiny health server on :8080. Fly.io's tcp_check probes
	// the port; the /health endpoint surfaces a JSON body with the
	// last-poll heartbeat for richer external monitoring (Better
	// Stack etc.). Port is configurable for local dev, defaults to
	// 8080 to match fly.toml.
	healthPort := os.Getenv("HEALTH_PORT")
	if healthPort == "" {
		healthPort = "8080"
	}
	// Live spectator hub — runs alongside the job-drain loop on the
	// same Go service. Picks Redis-backed pub/sub (multi-replica
	// fan-out, last-known TTL'd at 24h) when REDIS_URL is set,
	// otherwise falls back to the in-process Hub (single-replica /
	// dev path). Both satisfy `livehub.LivePubSub`.
	var hub livehub.LivePubSub
	if redisURL := os.Getenv("REDIS_URL"); redisURL != "" {
		rdb, err := livehub.ConfigureRedis(redisURL)
		if err != nil {
			logger.Error("livehub: REDIS_URL parse failed; falling back to in-process", "err", err)
			hub = livehub.NewHub()
		} else {
			redisHub := livehub.NewRedisHub(rdb)
			redisHub.Log = logger.With("component", "livehub-redis")
			hub = redisHub
			logger.Info("livehub: backend=redis (multi-replica fan-out)")
		}
	} else {
		hub = livehub.NewHub()
		logger.Info("livehub: backend=in-process (single-replica)")
	}
	// Privacy-zone fetcher. Wires the hub's push path to the
	// broadcaster's `user_settings.prefs.privacy_zones` so in-zone
	// pings are dropped before fan-out — same contract as the
	// `live_run_pings_drop_in_zone` trigger on the Supabase Realtime
	// path. Same service-role auth as the rest of the worker.
	zoneFetcher := &livehub.SupabaseZoneFetcher{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
		HTTP:       client.HTTP, // reuse the worker's pooled client
	}
	// JWT authorizer for the live hub. Source of truth is the
	// Supabase project's JWT secret (HS256). When SUPABASE_JWT_SECRET
	// is set the authorizer enforces:
	//   - push       : Bearer JWT required + sub == runs.user_id
	//   - subscribe  : owner-only on private runs, anon on public
	//   - snapshot   : same as subscribe
	// When unset the authorizer is nil and the hub stays permissive
	// (dev path). Production deploys MUST set the secret — fly.toml
	// + deployment.md document this.
	runMetaFetcher := &livehub.SupabaseRunMetaFetcher{
		BaseURL:    baseURL,
		ServiceKey: serviceKey,
		HTTP:       client.HTTP,
	}
	// Production fail-closed gate. audit/livehub H3 + H4: a deploy
	// that ships without SUPABASE_JWT_SECRET silently runs in
	// permissive mode (any caller can push pings as any user); a
	// deploy that ships without LIVEHUB_ALLOWED_ORIGINS accepts WS
	// upgrades from any origin. Both are catastrophic in prod and
	// fine in local dev. Gate on LIVEHUB_REQUIRE_AUTH=1 so the
	// developer experience is unchanged but prod cannot start
	// without the secrets.
	requireAuth := os.Getenv("LIVEHUB_REQUIRE_AUTH") == "1"
	jwtSecretEnv := os.Getenv("SUPABASE_JWT_SECRET")
	allowedOrigins := parseOrigins(os.Getenv("LIVEHUB_ALLOWED_ORIGINS"))
	if requireAuth {
		if jwtSecretEnv == "" {
			logger.Error("livehub: LIVEHUB_REQUIRE_AUTH=1 but SUPABASE_JWT_SECRET unset — refusing to start")
			os.Exit(1)
		}
		if len(allowedOrigins) == 0 {
			logger.Error("livehub: LIVEHUB_REQUIRE_AUTH=1 but LIVEHUB_ALLOWED_ORIGINS unset — refusing to start")
			os.Exit(1)
		}
	}

	authorizer := livehub.NewJWTAuthorizer(jwtSecretEnv, hub, runMetaFetcher)
	hubSrv := &livehub.Server{
		Hub:            hub,
		Log:            logger.With("component", "livehub"),
		AllowedOrigins: allowedOrigins,
		Zones:          zoneFetcher,
	}
	// Start the idle-room GC sweeper. Only the in-process Hub needs
	// it — the Redis backend's per-room key has a 24h TTL set on
	// every publish. /audit/livehub C2 + M4.
	if inProc, ok := hub.(*livehub.Hub); ok {
		inProc.StartGC(ctx, livehub.GCInterval, livehub.IdleRoomTTL)
		// Reap idle push-rate-limiter buckets on the same cadence — they
		// live on the Server, not the Hub, so the room GC above doesn't
		// touch them (they would otherwise leak one entry per distinct run).
		hubSrv.StartLimiterGC(ctx, livehub.GCInterval, livehub.IdleRoomTTL)
	}
	if authorizer != nil {
		hubSrv.Authorizer = authorizer.Authorize
		logger.Info("livehub auth: enabled (Supabase JWT)")
	} else {
		logger.Warn("livehub auth: DISABLED — SUPABASE_JWT_SECRET unset; permissive mode is for local dev only")
	}

	// Strava webhook receiver — mounts /v1/strava/webhook on the same
	// mux. Auth uses a shared URL secret + verify token (mirrors the
	// EF's contract); the body filter / dedupe / freshness gates live
	// in `internal/stravahook/server.go`. Events pass validation,
	// enqueue a `strava_event` job, and ack 200 in well under 2 s —
	// the worker's dispatch then does the activity fetch + Storage
	// upload async. See `apps/job_worker/deployment.md § Strava
	// webhook` for the cutover recipe.
	stravaWebhookSecret := os.Getenv("STRAVA_WEBHOOK_SECRET")
	stravaVerifyToken := os.Getenv("STRAVA_VERIFY_TOKEN")
	var stravaSrv *stravahook.Server
	if stravaWebhookSecret != "" && stravaVerifyToken != "" {
		stravaSrv = &stravahook.Server{
			WebhookSecret: stravaWebhookSecret,
			VerifyToken:   stravaVerifyToken,
			Enqueuer:      &stravaJobEnqueuer{client: client},
			WebhookEvents: client,
			Log:           logger.With("component", "stravahook"),
		}
		logger.Info("stravahook: enabled (Strava webhook endpoint mounted at /v1/strava/webhook)")
	} else {
		logger.Warn("stravahook: DISABLED — STRAVA_WEBHOOK_SECRET / STRAVA_VERIFY_TOKEN unset; webhook endpoint returns 503")
	}

	// Data export endpoint — POST /v1/export. JWT-authed (same
	// SUPABASE_JWT_SECRET the live hub uses), service-role for the
	// Storage upload + signed URL. Replaces the export-data Edge
	// Function. Refuses with 503 when the JWT secret isn't set —
	// matching the live hub's posture.
	var exportSrv *dataexport.Server
	if jwtSecret := os.Getenv("SUPABASE_JWT_SECRET"); jwtSecret != "" {
		exportSrv = &dataexport.Server{
			JWTSecret: []byte(jwtSecret),
			Backend:   &dataexportBackend{client: client},
			Log:       logger.With("component", "dataexport"),
		}
		logger.Info("dataexport: enabled (export endpoint mounted at /v1/export)")
	} else {
		logger.Warn("dataexport: DISABLED — SUPABASE_JWT_SECRET unset; export endpoint returns 503")
	}

	// Premium endpoints — Pro-tier-gated POSTs at /v1/premium/{vo2max,
	// race-predictor, recovery, training-plan}. Same JWT auth as the
	// data-export endpoint; an extra subscription_tier check before
	// the compute. Refuses with 503 when SUPABASE_JWT_SECRET unset.
	var premiumSrv *premium.Server
	if jwtSecret := os.Getenv("SUPABASE_JWT_SECRET"); jwtSecret != "" {
		premiumSrv = &premium.Server{
			JWTSecret: []byte(jwtSecret),
			Backend:   &premiumBackend{client: client},
			Log:       logger.With("component", "premium"),
		}
		logger.Info("premium: enabled (Pro endpoints mounted at /v1/premium/*)")
	} else {
		logger.Warn("premium: DISABLED — SUPABASE_JWT_SECRET unset; Pro endpoints return 503")
	}

	// Weekly-digest unsubscribe endpoint — unauthenticated RFC 8058 one-click
	// opt-out at /unsubscribe/weekly-digest. The stateless HMAC token is the
	// credential (no session); verifying it flips the opt-in pref to 'off' and
	// inserts an email_suppressions row. Refuses with 503 when the secret is
	// unset — same fail-closed posture as the JWT-gated endpoints. This is the
	// opt-OUT side; it is safe to enable independently of any digest SEND
	// (which stays gated on no scheduled builder existing).
	var unsubSrv *unsubscribe.Server
	if digestUnsubSecret != "" {
		unsubSrv = &unsubscribe.Server{
			Secret:  digestUnsubSecret,
			Backend: &unsubscribeBackend{client: client},
			Log:     logger.With("component", "unsubscribe"),
		}
		logger.Info("unsubscribe: enabled (weekly-digest opt-out mounted at /unsubscribe/weekly-digest)")
	} else {
		logger.Warn("unsubscribe: DISABLED — WEEKLY_DIGEST_UNSUB_SECRET unset; unsubscribe endpoint returns 503 + digest renders without a List-Unsubscribe link")
	}

	// Email bounce/complaint webhook — POST /v1/email/bounce. The provider
	// (Resend / SES) calls this on a hard bounce or spam complaint; the
	// handler adds the address to email_suppressions so no future bulk send
	// re-mails it (the hard block the digest builder consults independently of
	// the recipient pref). Shared-secret authed (same posture as the Strava
	// hook). Refuses with 503 when EMAIL_BOUNCE_WEBHOOK_SECRET is unset — the
	// consistent fail-closed posture. *SupabaseClient satisfies bouncehook.Backend
	// directly (InsertEmailSuppression already exists).
	var bounceSrv *bouncehook.Server
	if bounceSecret := os.Getenv("EMAIL_BOUNCE_WEBHOOK_SECRET"); bounceSecret != "" {
		bounceSrv = &bouncehook.Server{
			Secret:  bounceSecret,
			Backend: client,
			Log:     logger.With("component", "bouncehook"),
		}
		logger.Info("bouncehook: enabled (bounce/complaint webhook mounted at /v1/email/bounce)")
	} else {
		logger.Warn("bouncehook: DISABLED — EMAIL_BOUNCE_WEBHOOK_SECRET unset; bounce webhook returns 503 (suppression list won't grow from provider events)")
	}

	healthSrv := startHealthServer(logger, healthPort, &lastClaimAtUnix, workerID, hubSrv, stravaSrv, exportSrv, premiumSrv, unsubSrv, bounceSrv)
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = healthSrv.Shutdown(shutdownCtx)
	}()

	if err := worker.Run(ctx); err != nil {
		logger.Error("worker exited", "err", err)
		os.Exit(1)
	}
}

// startHealthServer mounts a /health endpoint on the configured port
// and returns the running server. The caller is expected to Shutdown
// it on exit.
//
// /health returns:
//   - 200 + `{"status":"ok",...}` while the worker poll loop is
//     ticking (heartbeat seen within 5 × PollInterval).
//   - 503 + `{"status":"stale",...}` when the heartbeat is stale —
//     Fly's auto-restart kicks in on repeated 503s.
//
// The grace period (5 × PollInterval = 10s) accommodates a job that
// happens to take that long to handle; longer-running jobs would
// trigger a restart, which is the correct response for "this job is
// hung".
func startHealthServer(log *slog.Logger, port string, lastClaim *atomic.Int64, workerID string, hub *livehub.Server, strava *stravahook.Server, export *dataexport.Server, prem *premium.Server, unsub *unsubscribe.Server, bounce *bouncehook.Server) *http.Server {
	mux := http.NewServeMux()
	if hub != nil {
		hub.RegisterRoutes(mux)
	}
	if strava != nil {
		strava.RegisterRoutes(mux)
	}
	if export != nil {
		export.RegisterRoutes(mux)
	}
	if prem != nil {
		prem.RegisterRoutes(mux)
	}
	if unsub != nil {
		unsub.RegisterRoutes(mux)
	}
	if bounce != nil {
		bounce.RegisterRoutes(mux)
	}
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		ageSec := time.Now().Unix() - lastClaim.Load()
		w.Header().Set("Content-Type", "application/json")
		// 10s = 5 × default 2s PollInterval. If the loop ticks every
		// 2s in the steady state, anything over 10s means it's stuck.
		if ageSec > 10 {
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, `{"status":"stale","worker_id":%q,"poll_age_s":%d}`, workerID, ageSec)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","worker_id":%q,"poll_age_s":%d}`, workerID, ageSec)
	})

	srv := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		log.Info("health server listening", "port", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("health server failed", "err", err)
		}
	}()
	return srv
}

// parseOrigins splits a comma-separated env value into the
// AllowedOrigins list the WS upgrade enforces. Empty input → empty
// slice (caller treats as "skip origin check", which is fine for
// local dev / smoke tests; production sets at least one host).
func parseOrigins(env string) []string {
	if env == "" {
		return nil
	}
	parts := strings.Split(env, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func requireEnv(log *slog.Logger, name string) string {
	v := os.Getenv(name)
	if v == "" {
		log.Error("missing required env var", "name", name)
		os.Exit(2)
	}
	return v
}
