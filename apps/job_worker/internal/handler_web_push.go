package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/Absence0760/project-running/apps/job_worker/internal/webpush"
)

// handleWebPush drains a `web_push` job: load the referenced notification,
// decide whether the recipient wants this category by push, load their browser
// push subscriptions, and send an encrypted Web Push message to each. Enqueued
// one-per-row by the notifications AFTER INSERT trigger (migration
// 20261219_001) — the sibling of the notification_email enqueue. The
// notifications row is the single source of truth shared with the in-app bell
// and the email channel; this is the *web-push* consumer. A native FCM/APNs
// sender would be another sibling — operator-credential-blocked, separate leg.
//
// Terminal-state discipline mirrors the email handler: every path that won't
// send (opted out, no subscription) stamps web_push_sent_at so the row is
// considered exactly once. The one exception is "sender not configured", which
// finishes the job done WITHOUT stamping so a later VAPID-enabled deploy can
// still send the still-pending rows.
//
// Delivery is at-least-once. A dead subscription (404/410) is pruned and
// treated as handled. A transient failure (429/5xx/network) on any
// subscription returns an error so the queue retries the whole job; the Tag on
// the payload (notif-<id>) coalesces the re-send on the client so a duplicate
// replaces rather than stacks.
func (w *Worker) handleWebPush(ctx context.Context, job *Job) error {
	if w.WebPush == nil {
		// No VAPID keypair configured. Finish done without stamping: the
		// notification stays pending so a later push-enabled deploy can send
		// it (same posture as the email handler's nil-sender branch).
		w.Log.Info("web_push: sender not configured; leaving row pending")
		return nil
	}

	var p WebPushPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.NotificationID == "" {
		return errors.New("payload missing notification_id")
	}

	n, err := w.Backend.FetchNotificationForWebPush(ctx, p.NotificationID)
	if err != nil {
		return fmt.Errorf("fetch notification: %w", err)
	}
	if n == nil {
		w.Log.Info("web_push: notification gone (inbox cleared)", "id", p.NotificationID)
		return nil
	}
	if n.WebPushSentAt != nil {
		// Already handled (re-enqueue or post-send retry). Idempotent.
		return nil
	}

	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !shouldPush(n.Kind, pushMode(prefs)) {
		// Recipient opted this category out of the push channel. Terminal.
		return w.Backend.MarkNotificationWebPushed(ctx, n.ID)
	}

	subs, err := w.Backend.FetchPushSubscriptions(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch subscriptions: %w", err)
	}
	if len(subs) == 0 {
		// No browser registered for push. Terminal — nothing to send, and a
		// later subscribe shouldn't retro-deliver an old notification.
		return w.Backend.MarkNotificationWebPushed(ctx, n.ID)
	}

	payload, err := renderWebPushPayload(*n, w.AppBaseURL, localeFromPrefs(prefs))
	if err != nil {
		return fmt.Errorf("render payload: %w", err)
	}

	var transient *HTTPError
	for _, s := range subs {
		status, sendErr := w.WebPush.Send(ctx, webpush.Subscription{
			Endpoint: s.Endpoint,
			P256dh:   s.P256dh,
			Auth:     s.Auth,
		}, payload)
		switch {
		case sendErr != nil:
			// Transport failure (DNS, dial, reset) — retry the whole job.
			w.Log.Warn("web_push: transport error", "device_id", s.DeviceID, "err", sendErr)
			transient = &HTTPError{StatusCode: http.StatusServiceUnavailable, Body: sendErr.Error()}
		case status == http.StatusNotFound || status == http.StatusGone:
			// The subscription is dead (browser unsubscribed / expired).
			// Prune it so it stops being retried for every future
			// notification. Best-effort — a failed prune isn't worth failing
			// the job over.
			w.Log.Info("web_push: pruning dead subscription", "device_id", s.DeviceID, "status", status)
			if err := w.Backend.ClearPushSubscription(ctx, n.UserID, s.DeviceID); err != nil {
				w.Log.Warn("web_push: prune failed", "device_id", s.DeviceID, "err", err)
			}
		case status == http.StatusTooManyRequests || status >= 500:
			// Push service throttling or down — retry the whole job.
			w.Log.Warn("web_push: transient push-service status", "device_id", s.DeviceID, "status", status)
			transient = &HTTPError{StatusCode: status}
		case status >= 200 && status < 300:
			w.Log.Info("web_push: sent", "kind", n.Kind, "device_id", s.DeviceID, "status", status)
		default:
			// Other 4xx (400 bad payload, 413 too large) — permanent for this
			// subscription. Drop it from this send; don't fail the job.
			w.Log.Warn("web_push: permanent push-service status; dropping", "device_id", s.DeviceID, "status", status)
		}
	}

	if transient != nil {
		// At least one delivery should be retried. Don't stamp — the next
		// attempt re-sends (Tag coalesces on the client).
		return transient
	}
	if err := w.Backend.MarkNotificationWebPushed(ctx, n.ID); err != nil {
		return fmt.Errorf("mark sent: %w", err)
	}
	return nil
}
