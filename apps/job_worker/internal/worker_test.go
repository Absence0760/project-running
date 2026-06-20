package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeBackend records every call so tests can pin the worker's
// finish/defer/upload behaviour without a real Supabase. Pure data —
// no network, no goroutines — so tests run in milliseconds.
type fakeBackend struct {
	mu sync.Mutex

	// Inputs
	jobs        []*Job // queued in order; ClaimNextJob pops from the front
	trackByPath map[string][]TrackPoint
	trackURL    string
	// Optional override: when non-nil, ReadRunTrackURL returns
	// trackURLs[i] on the i-th call (clamped to the last entry).
	// Lets tests simulate a re-upload mid-match — the worker reads
	// trackURL at start, then re-reads before writing, and the
	// second read returns the new URL.
	trackURLs []string
	// Auto-link inputs
	autoLinkInfo    RunLinkInfo
	autoLinkInfoErr error
	routeCandidates []RouteMatchCandidate
	findRoutesErr   error
	linkErr         error
	// Auto-link outputs
	links []linkCall
	// CAS: when non-empty, UpdateMatchedTrackRow returns
	// ErrStaleSourceTrackURL whenever the worker's
	// expectedSourceTrackURL doesn't equal this value. Lets a test
	// model "trigger reset the row between recheck and PATCH".
	casExpected string

	// Errors to inject — return on the next call to that method.
	claimErr     error
	downloadErr  error
	uploadErr    error
	updateRowErr error
	readURLErr   error
	matcherErr   error // not on the backend, but threaded through
	finishErr    error
	deferErr     error
	// deferStatus is the status DeferJob reports back (mirrors the
	// defer_job RPC return). Empty → "queued"; set to "failed" to
	// simulate the worker deferring a job whose retry budget is spent.
	deferStatus string

	// downloadDelay, when non-zero, makes DownloadTrack block for
	// that duration OR until the caller's context is cancelled.
	// Used by the HandleTimeout test to simulate a wedged Storage
	// download that exceeds the worker's per-job deadline.
	downloadDelay time.Duration

	// photo_process inputs/outputs — keyed by storage_path. The
	// fake echoes back whatever's stored; the handler's strip path
	// asserts on the post-upload bytes.
	photoByPath              map[string][]byte
	photoContentType         string
	downloadPhotoErr         error
	uploadPhotoErr           error
	photoUploadedContentType string
	// thumb_512_path PATCH path — photoThumbPaths records every
	// (photo_id → thumb_path) the handler pushes.
	photoThumbPaths     map[string]string
	updatePhotoThumbErr error

	// notification_email inputs/outputs.
	notifications  map[string]*NotificationRow       // keyed by id; absent → (nil,nil)
	userPrefs      map[string]map[string]interface{} // keyed by user_id
	userEmails     map[string]string                 // keyed by user_id
	fetchNotifErr  error
	fetchPrefsErr  error
	fetchEmailErr  error
	markEmailedErr error
	markedEmailed  []string // notification ids stamped email_sent_at

	// lifecycle_email inputs/outputs.
	lifecycleSent      map[string]bool // key "user_id|template" → already sent
	lifecycleSentErr   error
	recordLifecycleErr error
	recordedLifecycle  []string // "user_id|template" recorded this run

	receiptSent      map[string]bool // key email_hash → already sent
	receiptSentErr   error
	recordReceiptErr error
	recordedReceipts []string // email hashes recorded this run

	// web_push inputs/outputs.
	pushSubs        map[string][]PushSubscriptionRow // keyed by user_id
	fetchSubsErr    error
	markWebPushErr  error
	clearSubErr     error
	markedWebPushed []string // notification ids stamped web_push_sent_at
	clearedSubs     []string // "user_id|device_id" pruned this run

	// native_push inputs/outputs.
	deviceTokens       map[string][]DeviceTokenRow // keyed by user_id
	fetchTokensErr     error
	markNativePushErr  error
	clearTokenErr      error
	markedNativePushed []string // notification ids stamped native_push_sent_at
	clearedTokens      []string // tokens pruned this run

	// weekly_digest inputs.
	suppressed     map[string]bool // keyed by email → on the hard-block list
	suppressErr    error
	digestByUser   map[string]DigestSummary // keyed by user_id → the weekly summary
	buildDigestErr error

	// Outputs
	finished []finishCall
	deferred []deferCall
	uploaded map[string][]TrackPoint
	rowSets  []rowSet

	// token_refresh inputs
	expiring             []IntegrationRow
	fetchExpiringErr     error
	fetchExpiringWindows []time.Duration
	tokensByUser         map[string]TokenPair
	getTokenErrs         map[string]error
	setTokenErrs         map[string]error
	// token_refresh outputs
	getTokenCalls         []string
	setTokenCalls         []setTokenCall
	markDisconnectedCalls []markDisconnectedCall
	// quotaAllowOverride: nil → always allow. Pointer-to-false →
	// always deny. /audit/strava M7 test seam.
	quotaAllowOverride *bool
	// strava_event inputs
	integrationByAthlete map[int64]string
	findIntegrationErr   error
	alreadyImported      map[importedKey]bool
	isAlreadyImportedErr error
	insertStravaRunErr   error
	webhookEvents        map[string]bool
	insertWebhookErr     error
	// strava_event outputs
	insertedStravaRuns []insertedStravaRun
	trackURLPatches    []trackURLPatch
	webhookDeletes     []string
}

type finishCall struct {
	JobID    int64
	Status   string
	ErrorMsg *string
}

type deferCall struct {
	JobID  int64
	DelayS int
	ErrMsg *string
}

type rowSet struct {
	RunID string
	Row   MatchedTrackRow
}

type linkCall struct {
	RunID   string
	RouteID string
}

func newFakeBackend() *fakeBackend {
	return &fakeBackend{
		trackByPath:          map[string][]TrackPoint{},
		uploaded:             map[string][]TrackPoint{},
		tokensByUser:         map[string]TokenPair{},
		getTokenErrs:         map[string]error{},
		setTokenErrs:         map[string]error{},
		integrationByAthlete: map[int64]string{},
		alreadyImported:      map[importedKey]bool{},
		webhookEvents:        map[string]bool{},
	}
}

func (f *fakeBackend) ClaimNextJob(_ context.Context, _, _ string) (*Job, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.claimErr != nil {
		err := f.claimErr
		f.claimErr = nil
		return nil, err
	}
	if len(f.jobs) == 0 {
		return nil, nil
	}
	job := f.jobs[0]
	f.jobs = f.jobs[1:]
	return job, nil
}

func (f *fakeBackend) FinishJob(_ context.Context, jobID int64, status string, msg *string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.finishErr != nil {
		err := f.finishErr
		f.finishErr = nil
		return err
	}
	f.finished = append(f.finished, finishCall{JobID: jobID, Status: status, ErrorMsg: msg})
	return nil
}

func (f *fakeBackend) DeferJob(_ context.Context, jobID int64, delay int, msg *string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.deferErr != nil {
		err := f.deferErr
		f.deferErr = nil
		return "", err
	}
	f.deferred = append(f.deferred, deferCall{JobID: jobID, DelayS: delay, ErrMsg: msg})
	if f.deferStatus != "" {
		return f.deferStatus, nil
	}
	return "queued", nil
}

// Photo-process surface — used by handler_photo_process_test.go.
// The existing track-handler tests don't touch these and don't
// care about their state; per-test setUp overrides `photoByPath`
// or `uploadPhotoErr` when they need different behaviour.
func (f *fakeBackend) DownloadPhoto(_ context.Context, path string) ([]byte, string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.downloadPhotoErr != nil {
		err := f.downloadPhotoErr
		f.downloadPhotoErr = nil
		return nil, "", err
	}
	b, ok := f.photoByPath[path]
	if !ok {
		return nil, "", errors.New("photo not found in fake backend: " + path)
	}
	ct := f.photoContentType
	if ct == "" {
		ct = "image/jpeg"
	}
	return b, ct, nil
}

func (f *fakeBackend) UploadPhoto(_ context.Context, path string, body []byte, contentType string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.uploadPhotoErr != nil {
		err := f.uploadPhotoErr
		f.uploadPhotoErr = nil
		return err
	}
	if f.photoByPath == nil {
		f.photoByPath = make(map[string][]byte)
	}
	f.photoByPath[path] = body
	f.photoUploadedContentType = contentType
	return nil
}

func (f *fakeBackend) UpdatePhotoThumb512Path(_ context.Context, photoID, path string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.updatePhotoThumbErr != nil {
		err := f.updatePhotoThumbErr
		f.updatePhotoThumbErr = nil
		return err
	}
	if f.photoThumbPaths == nil {
		f.photoThumbPaths = make(map[string]string)
	}
	f.photoThumbPaths[photoID] = path
	return nil
}

// The route-photo methods share the run-photo fake's storage map +
// error fields — the two handlers exercise the identical strip/thumbnail
// path, only the bucket + table differ in production. A route-photo test
// sets up photoByPath / photoThumbPaths / the *PhotoErr fields the same way.
func (f *fakeBackend) DownloadRoutePhoto(ctx context.Context, path string) ([]byte, string, error) {
	return f.DownloadPhoto(ctx, path)
}

func (f *fakeBackend) UploadRoutePhoto(ctx context.Context, path string, body []byte, contentType string) error {
	return f.UploadPhoto(ctx, path, body, contentType)
}

func (f *fakeBackend) UpdateRoutePhotoThumb512Path(ctx context.Context, photoID, path string) error {
	return f.UpdatePhotoThumb512Path(ctx, photoID, path)
}

func (f *fakeBackend) FetchNotificationForEmail(_ context.Context, id string) (*NotificationRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchNotifErr != nil {
		err := f.fetchNotifErr
		f.fetchNotifErr = nil
		return nil, err
	}
	return f.notifications[id], nil
}

func (f *fakeBackend) FetchUserSettingsPrefs(_ context.Context, userID string) (map[string]interface{}, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchPrefsErr != nil {
		err := f.fetchPrefsErr
		f.fetchPrefsErr = nil
		return nil, err
	}
	if p, ok := f.userPrefs[userID]; ok {
		return p, nil
	}
	return map[string]interface{}{}, nil
}

func (f *fakeBackend) FetchUserEmail(_ context.Context, userID string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchEmailErr != nil {
		err := f.fetchEmailErr
		f.fetchEmailErr = nil
		return "", err
	}
	return f.userEmails[userID], nil
}

func (f *fakeBackend) MarkNotificationEmailed(_ context.Context, id string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.markEmailedErr != nil {
		err := f.markEmailedErr
		f.markEmailedErr = nil
		return err
	}
	f.markedEmailed = append(f.markedEmailed, id)
	if n := f.notifications[id]; n != nil {
		stamped := "2026-01-01T00:00:00Z"
		n.EmailSentAt = &stamped
	}
	return nil
}

func (f *fakeBackend) LifecycleEmailAlreadySent(_ context.Context, userID, template string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.lifecycleSentErr != nil {
		err := f.lifecycleSentErr
		f.lifecycleSentErr = nil
		return false, err
	}
	return f.lifecycleSent[userID+"|"+template], nil
}

func (f *fakeBackend) RecordLifecycleEmail(_ context.Context, userID, template string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.recordLifecycleErr != nil {
		err := f.recordLifecycleErr
		f.recordLifecycleErr = nil
		return err
	}
	key := userID + "|" + template
	f.recordedLifecycle = append(f.recordedLifecycle, key)
	if f.lifecycleSent == nil {
		f.lifecycleSent = map[string]bool{}
	}
	f.lifecycleSent[key] = true
	return nil
}

func (f *fakeBackend) AccountDeletionReceiptAlreadySent(_ context.Context, emailHash string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.receiptSentErr != nil {
		err := f.receiptSentErr
		f.receiptSentErr = nil
		return false, err
	}
	return f.receiptSent[emailHash], nil
}

func (f *fakeBackend) RecordAccountDeletionReceipt(_ context.Context, emailHash string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.recordReceiptErr != nil {
		err := f.recordReceiptErr
		f.recordReceiptErr = nil
		return err
	}
	f.recordedReceipts = append(f.recordedReceipts, emailHash)
	if f.receiptSent == nil {
		f.receiptSent = map[string]bool{}
	}
	f.receiptSent[emailHash] = true
	return nil
}

func (f *fakeBackend) FetchNotificationForWebPush(_ context.Context, id string) (*NotificationRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchNotifErr != nil {
		err := f.fetchNotifErr
		f.fetchNotifErr = nil
		return nil, err
	}
	return f.notifications[id], nil
}

func (f *fakeBackend) MarkNotificationWebPushed(_ context.Context, id string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.markWebPushErr != nil {
		err := f.markWebPushErr
		f.markWebPushErr = nil
		return err
	}
	f.markedWebPushed = append(f.markedWebPushed, id)
	if n := f.notifications[id]; n != nil {
		stamped := "2026-01-01T00:00:00Z"
		n.WebPushSentAt = &stamped
	}
	return nil
}

func (f *fakeBackend) FetchPushSubscriptions(_ context.Context, userID string) ([]PushSubscriptionRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchSubsErr != nil {
		err := f.fetchSubsErr
		f.fetchSubsErr = nil
		return nil, err
	}
	return f.pushSubs[userID], nil
}

func (f *fakeBackend) ClearPushSubscription(_ context.Context, userID, deviceID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.clearSubErr != nil {
		err := f.clearSubErr
		f.clearSubErr = nil
		return err
	}
	f.clearedSubs = append(f.clearedSubs, userID+"|"+deviceID)
	return nil
}

func (f *fakeBackend) FetchNotificationForNativePush(_ context.Context, id string) (*NotificationRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchNotifErr != nil {
		err := f.fetchNotifErr
		f.fetchNotifErr = nil
		return nil, err
	}
	return f.notifications[id], nil
}

func (f *fakeBackend) MarkNotificationNativePushed(_ context.Context, id string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.markNativePushErr != nil {
		err := f.markNativePushErr
		f.markNativePushErr = nil
		return err
	}
	f.markedNativePushed = append(f.markedNativePushed, id)
	if n := f.notifications[id]; n != nil {
		stamped := "2026-01-01T00:00:00Z"
		n.NativePushSentAt = &stamped
	}
	return nil
}

func (f *fakeBackend) FetchDeviceTokens(_ context.Context, userID string) ([]DeviceTokenRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchTokensErr != nil {
		err := f.fetchTokensErr
		f.fetchTokensErr = nil
		return nil, err
	}
	return f.deviceTokens[userID], nil
}

func (f *fakeBackend) ClearDeviceToken(_ context.Context, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.clearTokenErr != nil {
		err := f.clearTokenErr
		f.clearTokenErr = nil
		return err
	}
	f.clearedTokens = append(f.clearedTokens, token)
	return nil
}

func (f *fakeBackend) IsEmailSuppressed(_ context.Context, email string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.suppressErr != nil {
		err := f.suppressErr
		f.suppressErr = nil
		return false, err
	}
	return f.suppressed[email], nil
}

func (f *fakeBackend) BuildWeeklyDigest(_ context.Context, userID string, _ time.Time) (DigestSummary, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.buildDigestErr != nil {
		err := f.buildDigestErr
		f.buildDigestErr = nil
		return DigestSummary{}, err
	}
	return f.digestByUser[userID], nil
}

func (f *fakeBackend) DownloadTrack(ctx context.Context, path string) ([]TrackPoint, error) {
	f.mu.Lock()
	delay := f.downloadDelay
	f.mu.Unlock()
	if delay > 0 {
		// Honour ctx.Done so a per-job HandleTimeout can interrupt
		// a wedged download. This is the property the worker's
		// `context.WithTimeout` is supposed to enforce — pin it
		// via the timeout test below.
		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}

	f.mu.Lock()
	defer f.mu.Unlock()
	if f.downloadErr != nil {
		err := f.downloadErr
		f.downloadErr = nil
		return nil, err
	}
	pts, ok := f.trackByPath[path]
	if !ok {
		return nil, errors.New("track not found in fake backend: " + path)
	}
	return pts, nil
}

func (f *fakeBackend) UploadMatchedTrack(_ context.Context, path string, pts []TrackPoint) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.uploadErr != nil {
		err := f.uploadErr
		f.uploadErr = nil
		return err
	}
	f.uploaded[path] = pts
	return nil
}

func (f *fakeBackend) UpdateMatchedTrackRow(
	_ context.Context, runID string, expectedSourceTrackURL string, row MatchedTrackRow,
) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.updateRowErr != nil {
		err := f.updateRowErr
		f.updateRowErr = nil
		return err
	}
	// CAS: the test sets `casExpected` to whatever the row's
	// source_track_url is "currently". Mismatch surfaces the same
	// sentinel the production client returns.
	if expectedSourceTrackURL != "" && f.casExpected != "" &&
		expectedSourceTrackURL != f.casExpected {
		return ErrStaleSourceTrackURL
	}
	f.rowSets = append(f.rowSets, rowSet{RunID: runID, Row: row})
	return nil
}

func (f *fakeBackend) ReadRunForAutoLink(_ context.Context, _ string) (RunLinkInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.autoLinkInfoErr != nil {
		err := f.autoLinkInfoErr
		f.autoLinkInfoErr = nil
		return RunLinkInfo{}, err
	}
	return f.autoLinkInfo, nil
}

func (f *fakeBackend) FindMatchingRoutes(
	_ context.Context, _ string, _ []TrackPoint, _ float64, _ int,
) ([]RouteMatchCandidate, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.findRoutesErr != nil {
		err := f.findRoutesErr
		f.findRoutesErr = nil
		return nil, err
	}
	return f.routeCandidates, nil
}

func (f *fakeBackend) LinkRunToRoute(_ context.Context, runID, routeID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.linkErr != nil {
		err := f.linkErr
		f.linkErr = nil
		return err
	}
	f.links = append(f.links, linkCall{RunID: runID, RouteID: routeID})
	return nil
}

func (f *fakeBackend) ReadRunTrackURL(_ context.Context, _ string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.readURLErr != nil {
		err := f.readURLErr
		f.readURLErr = nil
		return "", err
	}
	if len(f.trackURLs) > 0 {
		// Return the next scripted URL, sticking on the last entry
		// once the script runs out (extra reads behave like the
		// final state).
		url := f.trackURLs[0]
		if len(f.trackURLs) > 1 {
			f.trackURLs = f.trackURLs[1:]
		}
		return url, nil
	}
	return f.trackURL, nil
}

// --- token_refresh fake state ---

// Token-refresh test inputs/outputs are kept on the same fakeBackend
// so a single test wires one backend, one matcher, one Strava fake.
// Default zero values are safe: no expiring rows + no Vault tokens
// means a token_refresh job is a no-op (matches the "no expiring
// tokens" production branch).
func (f *fakeBackend) FetchExpiringStravaIntegrations(_ context.Context, within time.Duration) ([]IntegrationRow, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fetchExpiringErr != nil {
		err := f.fetchExpiringErr
		f.fetchExpiringErr = nil
		return nil, err
	}
	f.fetchExpiringWindows = append(f.fetchExpiringWindows, within)
	return append([]IntegrationRow(nil), f.expiring...), nil
}

func (f *fakeBackend) GetIntegrationTokens(_ context.Context, userID, provider string) (*TokenPair, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.getTokenCalls = append(f.getTokenCalls, userID+":"+provider)
	if err, ok := f.getTokenErrs[userID]; ok {
		return nil, err
	}
	tok, ok := f.tokensByUser[userID]
	if !ok {
		return nil, nil
	}
	cp := tok
	return &cp, nil
}

func (f *fakeBackend) SetIntegrationTokens(_ context.Context, userID, provider, access, refresh string, expiry time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err, ok := f.setTokenErrs[userID]; ok {
		return err
	}
	f.setTokenCalls = append(f.setTokenCalls, setTokenCall{
		UserID:       userID,
		Provider:     provider,
		AccessToken:  access,
		RefreshToken: refresh,
		Expiry:       expiry,
	})
	// Mirror production: rotation updates the in-memory pair so a
	// subsequent GetIntegrationTokens returns the new value.
	f.tokensByUser[userID] = TokenPair{AccessToken: access, RefreshToken: refresh}
	return nil
}

type setTokenCall struct {
	UserID       string
	Provider     string
	AccessToken  string
	RefreshToken string
	Expiry       time.Time
}

// markDisconnectedCall captures the args fakeBackend.MarkIntegration
// Disconnected was called with. /audit/strava High #2.
type markDisconnectedCall struct {
	UserID   string
	Provider string
	Reason   string
}

// TryConsumeStravaQuota stub. Tests can override
// `quotaAllowOverride` to simulate a quota-exhausted state.
// /audit/strava M7.
func (f *fakeBackend) TryConsumeStravaQuota(_ context.Context) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.quotaAllowOverride != nil {
		return *f.quotaAllowOverride, nil
	}
	return true, nil
}

// SetIntegrationTokensCAS stub mirrors the production semantics
// (compare expectedRefresh vs current, write only if match).
// /audit/strava High #3.
func (f *fakeBackend) SetIntegrationTokensCAS(_ context.Context, userID, provider, expectedRefresh, access, refresh string, expiry time.Time) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err, ok := f.setTokenErrs[userID]; ok {
		return false, err
	}
	cur, ok := f.tokensByUser[userID]
	if !ok || cur.RefreshToken != expectedRefresh {
		return false, nil
	}
	f.setTokenCalls = append(f.setTokenCalls, setTokenCall{
		UserID:       userID,
		Provider:     provider,
		AccessToken:  access,
		RefreshToken: refresh,
		Expiry:       expiry,
	})
	f.tokensByUser[userID] = TokenPair{AccessToken: access, RefreshToken: refresh}
	return true, nil
}

func (f *fakeBackend) MarkIntegrationDisconnected(_ context.Context, userID, provider, reason string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.markDisconnectedCalls = append(f.markDisconnectedCalls, markDisconnectedCall{
		UserID:   userID,
		Provider: provider,
		Reason:   reason,
	})
	return nil
}

// --- strava_event fake state ---

func (f *fakeBackend) FindIntegrationUserByAthlete(_ context.Context, _ string, athleteID int64) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.findIntegrationErr != nil {
		err := f.findIntegrationErr
		f.findIntegrationErr = nil
		return "", err
	}
	return f.integrationByAthlete[athleteID], nil
}

func (f *fakeBackend) IsStravaActivityImported(_ context.Context, userID string, activityID int64) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.isAlreadyImportedErr != nil {
		err := f.isAlreadyImportedErr
		f.isAlreadyImportedErr = nil
		return false, err
	}
	return f.alreadyImported[importedKey{userID, activityID}], nil
}

func (f *fakeBackend) InsertStravaRun(_ context.Context, userID string, act *StravaActivity) (*IngestedRunInfo, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.insertStravaRunErr != nil {
		err := f.insertStravaRunErr
		f.insertStravaRunErr = nil
		return nil, err
	}
	runID := fmt.Sprintf("run-%d", act.ID)
	f.insertedStravaRuns = append(f.insertedStravaRuns, insertedStravaRun{
		UserID: userID, ActivityID: act.ID, RunID: runID,
		ActivityType: act.Type, SportType: act.SportType,
	})
	return &IngestedRunInfo{ID: runID, UserID: userID}, nil
}

func (f *fakeBackend) UpdateRunTrackURL(_ context.Context, runID, trackURL string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.trackURLPatches = append(f.trackURLPatches, trackURLPatch{RunID: runID, URL: trackURL})
	return nil
}

func (f *fakeBackend) InsertWebhookEvent(_ context.Context, provider, eventID string) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.insertWebhookErr != nil {
		err := f.insertWebhookErr
		f.insertWebhookErr = nil
		return false, err
	}
	key := provider + ":" + eventID
	if f.webhookEvents[key] {
		return false, nil
	}
	f.webhookEvents[key] = true
	return true, nil
}

func (f *fakeBackend) DeleteWebhookEvent(_ context.Context, provider, eventID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.webhookEvents, provider+":"+eventID)
	f.webhookDeletes = append(f.webhookDeletes, provider+":"+eventID)
	return nil
}

type importedKey struct {
	UserID     string
	ActivityID int64
}

type insertedStravaRun struct {
	UserID       string
	ActivityID   int64
	RunID        string
	ActivityType string
	SportType    string
}

type trackURLPatch struct {
	RunID string
	URL   string
}

// fakeStrava is the StravaIngestor stub the token-refresh and
// strava_event tests use. Each call returns the next scripted
// response; errors are scripted by token / activity id so a mid-loop
// failure can be modelled without poisoning the other rows.
type fakeStrava struct {
	mu          sync.Mutex
	byToken     map[string]StravaTokenResponse
	errsByToken map[string]error
	calls       []string // refresh tokens seen, in order
	// Optional probe invoked at the top of Refresh, OUTSIDE the mutex, so a
	// test can observe how many refreshes overlap (the bounded-concurrency
	// guard). Set once before the worker runs; never mutated concurrently.
	refreshHook func()
	// strava_event ingest stubs
	byActivity        map[int64]StravaActivityResult
	activityErrs      map[int64]error
	activityCalls     []int64
	streamsByActivity map[int64]map[string]StravaStream
	streamsErrs       map[int64]error
	streamsCalls      []int64
}

func (s *fakeStrava) Refresh(_ context.Context, refreshToken string) (*StravaTokenResponse, error) {
	if s.refreshHook != nil {
		s.refreshHook()
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls = append(s.calls, refreshToken)
	if err, ok := s.errsByToken[refreshToken]; ok {
		return nil, err
	}
	r, ok := s.byToken[refreshToken]
	if !ok {
		return nil, fmt.Errorf("no scripted response for token %q", refreshToken)
	}
	cp := r
	return &cp, nil
}

func (s *fakeStrava) FetchActivity(_ context.Context, _ string, activityID int64) (StravaActivityResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.activityCalls = append(s.activityCalls, activityID)
	if err, ok := s.activityErrs[activityID]; ok {
		return StravaActivityResult{}, err
	}
	r, ok := s.byActivity[activityID]
	if !ok {
		return StravaActivityResult{Status: StravaFetchNotFound}, nil
	}
	return r, nil
}

func (s *fakeStrava) FetchStreams(_ context.Context, _ string, activityID int64) (map[string]StravaStream, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.streamsCalls = append(s.streamsCalls, activityID)
	if err, ok := s.streamsErrs[activityID]; ok {
		return nil, err
	}
	return s.streamsByActivity[activityID], nil
}

// nopMatcher returns whatever it's told to, with the ability to inject
// an error. Used to drive Match success / failure / skip paths without
// touching the production passthrough.
type nopMatcher struct {
	err error
}

func (nopMatcher) Algorithm() string { return "test" }
func (nopMatcher) Version() string   { return "v1" }
func (m nopMatcher) Match(pts []TrackPoint) ([]TrackPoint, error) {
	if m.err != nil {
		return nil, m.err
	}
	return pts, nil
}

func newTestWorker(b Backend, m Matcher) *Worker {
	return &Worker{
		Backend: b,
		Matcher: m,
		Config: Config{
			WorkerID:       "test",
			PollInterval:   1 * time.Millisecond,
			HandleTimeout:  1 * time.Second,
			TransientDelay: 5,
		},
		Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
}

func mustPayload(t *testing.T, p MapMatchPayload) json.RawMessage {
	t.Helper()
	b, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// ---- happy path -------------------------------------------------------

func TestWorker_HappyPath(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.jobs = []*Job{{
		ID: 7, Kind: "map_match", Attempts: 1,
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})

	// Drain one job, then cancel.
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got, want := len(be.finished), 1; got != want {
		t.Fatalf("finished count=%d, want %d", got, want)
	}
	if be.finished[0].Status != "done" {
		t.Errorf("finish status=%q, want done", be.finished[0].Status)
	}

	if got, want := len(be.uploaded), 1; got != want {
		t.Fatalf("uploaded count=%d, want %d", got, want)
	}
	matchedPath := "user-1/run-1.matched.json.gz"
	if _, ok := be.uploaded[matchedPath]; !ok {
		t.Errorf("expected upload at %s, got %v", matchedPath, keys(be.uploaded))
	}

	if got, want := len(be.rowSets), 1; got != want {
		t.Fatalf("row sets=%d, want %d", got, want)
	}
	row := be.rowSets[0]
	if row.RunID != "run-1" || row.Row.Status != "matched" {
		t.Errorf("rowSet=%+v, want run-1/matched", row)
	}
	if row.Row.MatchedTrackURL != matchedPath {
		t.Errorf("matched_track_url=%q, want %q", row.Row.MatchedTrackURL, matchedPath)
	}
}

// ---- skipped path -----------------------------------------------------

func TestWorker_SkipsTooFewPoints(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	// One point. Matcher's passthrough returns 1; worker writes
	// 'skipped' rather than uploading a 1-point line.
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{{Lat: 1, Lng: 2}}
	be.jobs = []*Job{{
		ID: 9, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.uploaded) != 0 {
		t.Errorf("uploads on skip path: %v", keys(be.uploaded))
	}
	if len(be.rowSets) != 1 || be.rowSets[0].Row.Status != "skipped" {
		t.Errorf("rowSets=%+v, want one skipped row", be.rowSets)
	}
	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done", be.finished)
	}
}

// ---- re-upload race ---------------------------------------------------

// If track_url changes between the start of the match and the write
// back, the worker should discard its result and finish_job(done) so
// the OLD job exits cleanly. The trigger has already enqueued a new
// job for the fresh track; that one will produce the right result.
func TestWorker_ReuploadDuringMatchDiscardsResult(t *testing.T) {
	be := newFakeBackend()
	be.trackURLs = []string{
		"user-1/run-1.json.gz",    // first read (download)
		"user-1/run-1.v2.json.gz", // second read (recheck): re-upload landed
	}
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.jobs = []*Job{{
		ID: 21, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.uploaded); got != 0 {
		t.Errorf("uploaded count=%d, want 0 (stale result discarded)", got)
	}
	if got := len(be.rowSets); got != 0 {
		t.Errorf("row writes=%d, want 0 (stale result discarded)", got)
	}
	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want one done", be.finished)
	}
}

// ---- CAS race ----------------------------------------------------------

// Source-track-url CAS: when the trigger has reset the row's
// source_track_url between the worker's recheck and its PATCH, the
// PATCH targets zero rows and the worker discards cleanly. Same
// "OLD job exits done, NEW job already queued by trigger produces
// the right result" outcome as the recheck path — this closes the
// residual TOCTOU window that the recheck alone couldn't.
func TestWorker_StaleSourceTrackURLDiscardsResult(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	// Recheck would pass (URL matches). But the row's
	// source_track_url has already changed under the worker's
	// feet — UpdateMatchedTrackRow's CAS catches it.
	be.casExpected = "user-1/run-1.v2.json.gz"
	be.jobs = []*Job{{
		ID: 41, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.rowSets); got != 0 {
		t.Errorf("rowSets=%d, want 0 (CAS discarded the write)", got)
	}
	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done despite CAS miss", be.finished)
	}
}

// ---- transient retry path ---------------------------------------------

func TestWorker_TransientErrorDefers(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 503, Body: "upstream down"}
	be.jobs = []*Job{{
		ID: 11, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 0 {
		t.Errorf("transient error finished the job: %+v", be.finished)
	}
	if len(be.deferred) != 1 {
		t.Fatalf("deferred count=%d, want 1", len(be.deferred))
	}
	if be.deferred[0].DelayS != 5 {
		t.Errorf("delay_s=%d, want 5", be.deferred[0].DelayS)
	}
}

// When defer_job reports back "failed" (the retry budget was spent and
// the RPC terminated the job instead of re-queuing it), the worker must
// log it as a failure — not a deferral — so the log line matches the
// row the jobs-failed-alert surfaces. Regression guard for the silent
// "looks deferred but is actually dead" log.
func TestWorker_ExhaustedTransientLogsFailureNotDefer(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 503, Body: "upstream down"}
	be.deferStatus = "failed" // RPC says: budget exhausted, terminated
	be.jobs = []*Job{{
		ID: 11, Kind: "map_match", Attempts: 5,
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	var logBuf bytes.Buffer
	w := newTestWorker(be, PassthroughMatcher{})
	w.Log = slog.New(slog.NewTextHandler(&logBuf, &slog.HandlerOptions{Level: slog.LevelWarn}))

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	// The worker still calls DeferJob (the transient classification is
	// unchanged); the RPC decides re-queue vs terminate.
	if len(be.deferred) != 1 {
		t.Fatalf("deferred count=%d, want 1", len(be.deferred))
	}
	// The worker must NOT also call finish_job — defer_job did the
	// terminal transition server-side.
	if len(be.finished) != 0 {
		t.Errorf("exhausted transient also called finish_job: %+v", be.finished)
	}
	out := logBuf.String()
	if !strings.Contains(out, "job failed (retries exhausted)") {
		t.Errorf("missing exhausted-failure log line; got:\n%s", out)
	}
	if strings.Contains(out, "job deferred") {
		t.Errorf("logged a deferral for an exhausted job:\n%s", out)
	}
}

// The normal transient path (RPC reports "queued") still logs a
// deferral, not a failure.
func TestWorker_TransientRequeueLogsDeferral(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 503, Body: "upstream down"}
	// deferStatus left empty → fake returns "queued"
	be.jobs = []*Job{{
		ID: 12, Kind: "map_match", Attempts: 1,
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	var logBuf bytes.Buffer
	w := newTestWorker(be, PassthroughMatcher{})
	w.Log = slog.New(slog.NewTextHandler(&logBuf, &slog.HandlerOptions{Level: slog.LevelWarn}))

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	out := logBuf.String()
	if !strings.Contains(out, "job deferred") {
		t.Errorf("missing deferral log line; got:\n%s", out)
	}
	if strings.Contains(out, "retries exhausted") {
		t.Errorf("logged exhaustion for a re-queued job:\n%s", out)
	}
}

// ---- permanent failure path -------------------------------------------

func TestWorker_PermanentErrorFinishesFailed(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.downloadErr = &HTTPError{StatusCode: 404, Body: "not found"}
	be.jobs = []*Job{{
		ID: 13, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.deferred) != 0 {
		t.Errorf("404 was deferred (should be permanent): %+v", be.deferred)
	}
	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Fatalf("finish=%+v, want one failed", be.finished)
	}
	if be.finished[0].ErrorMsg == nil || !strings.Contains(*be.finished[0].ErrorMsg, "404") {
		t.Errorf("expected error message to carry 404, got %v", be.finished[0].ErrorMsg)
	}
}

// ---- malformed payload -------------------------------------------------

func TestWorker_BadPayloadFails(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{
		ID: 15, Kind: "map_match",
		Payload: json.RawMessage(`{"run_id":""}`),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Errorf("finish=%+v, want failed", be.finished)
	}
}

// ---- unknown kind ------------------------------------------------------

func TestWorker_UnknownKindFails(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{
		ID: 17, Kind: "send_carrier_pigeon",
		Payload: json.RawMessage(`{}`),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "failed" {
		t.Errorf("finish=%+v, want failed", be.finished)
	}
	if be.finished[0].ErrorMsg == nil || !strings.Contains(*be.finished[0].ErrorMsg, "unknown job kind") {
		t.Errorf("expected error mentioning unknown kind, got %v", be.finished[0].ErrorMsg)
	}
}

// ---- auto-link --------------------------------------------------------

// Confident match: endpoints close, length ratio under 20%. The
// worker should PATCH runs.route_id and the auto-link write happens
// once.
func TestWorker_AutoLinksWhenConfident(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-1",
		Name:         "morning loop",
		DistanceM:    1010, // 1% off the run's stored distance
		StartOffsetM: 5,
		EndOffsetM:   5,
	}}
	be.jobs = []*Job{{
		ID: 31, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 1 {
		t.Fatalf("links=%d, want 1", len(be.links))
	}
	if be.links[0].RunID != "run-1" || be.links[0].RouteID != "route-1" {
		t.Errorf("link=%+v, want run-1->route-1", be.links[0])
	}
	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done", be.finished)
	}
}

// Already-linked: route_id is non-empty, so the worker must NOT call
// FindMatchingRoutes / LinkRunToRoute. Idempotent on re-runs.
func TestWorker_NoAutoLinkWhenAlreadyLinked(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "already-linked", DistanceM: 1000}
	// Even if a candidate is on the table, we shouldn't query for it.
	be.routeCandidates = []RouteMatchCandidate{{
		ID: "ignored", StartOffsetM: 0, EndOffsetM: 0, DistanceM: 100,
	}}
	be.jobs = []*Job{{
		ID: 33, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (already linked)", be.links)
	}
}

// Length mismatch: candidate's distance is 50% off the track length.
// Even though endpoints are spot-on, the worker must NOT auto-link —
// this is the "run was a sub-section / superset" case the
// length-ratio check exists to catch.
func TestWorker_NoAutoLinkOnLengthMismatch(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-2",
		Name:         "5k loop",
		DistanceM:    5000, // 5x the run's distance — sub-section case
		StartOffsetM: 0,
		EndOffsetM:   0,
	}}
	be.jobs = []*Job{{
		ID: 35, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (length mismatch)", be.links)
	}
}

// Endpoint mismatch: lengths match but the start/end of the run is
// 500 m from the route's endpoints. Same neighbourhood, different
// run.
func TestWorker_NoAutoLinkOnEndpointMismatch(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 51.5074, Lng: -0.1278},
		{Lat: 51.5165, Lng: -0.1278},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.routeCandidates = []RouteMatchCandidate{{
		ID:           "route-3",
		DistanceM:    1010,
		StartOffsetM: 250,
		EndOffsetM:   300, // sum = 550, > 200 m threshold
	}}
	be.jobs = []*Job{{
		ID: 37, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.links) != 0 {
		t.Errorf("links=%+v, want 0 (endpoints too far)", be.links)
	}
}

// Auto-link failure must NOT fail the job — the match itself
// succeeded, the auto-link is best-effort. Worker logs and returns.
func TestWorker_AutoLinkFailureDoesNotFailJob(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001}, {Lat: 1.002, Lng: 2.002},
	}
	be.autoLinkInfo = RunLinkInfo{RouteID: "", DistanceM: 1000}
	be.findRoutesErr = errors.New("rpc unavailable")
	be.jobs = []*Job{{
		ID: 39, Kind: "map_match",
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 1 || be.finished[0].Status != "done" {
		t.Errorf("finish=%+v, want done despite auto-link failure", be.finished)
	}
	if len(be.rowSets) != 1 || be.rowSets[0].Row.Status != "matched" {
		t.Errorf("rowSets=%+v, want one matched", be.rowSets)
	}
}

// ---- isTransient classifier -------------------------------------------

func TestIsTransient(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{"5xx", &HTTPError{StatusCode: 503}, true},
		{"4xx", &HTTPError{StatusCode: 404}, false},
		{"timeout substring", errors.New("dial tcp: i/o timeout"), true},
		{"connection refused", errors.New("connection refused"), true},
		{"deadline exceeded", context.DeadlineExceeded, true},
		{"plain error", errors.New("payload missing run_id"), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isTransient(tc.err); got != tc.want {
				t.Errorf("isTransient(%v) = %v, want %v", tc.err, got, tc.want)
			}
		})
	}
}

// ---- HandleTimeout -----------------------------------------------------

// TestWorker_HandleTimeoutDefersStuckJob — pins the per-job timeout
// contract: when a job's runtime exceeds Config.HandleTimeout, the
// jobCtx is cancelled, the in-flight Backend call propagates
// context.DeadlineExceeded, isTransient classifies that as transient,
// and the worker calls defer_job (NOT finish_job(failed)).
//
// Why this matters: round-9 (`20260730_001_tier_aware_job_scheduling
// .sql`) made map-match priority depend on `scheduled_at` ordering,
// which only holds if no single job runs long enough to starve the
// queue. The HandleTimeout is the ceiling enforcement — if a Matcher
// hangs (wedged OSRM call, slow Storage download), the worker MUST
// cancel and defer rather than holding the worker slot indefinitely.
// Without this test a future refactor that dropped
// `context.WithTimeout` from worker.handle would silently break
// the run-to-completion-OR-cancel contract.
func TestWorker_HandleTimeoutDefersStuckJob(t *testing.T) {
	be := newFakeBackend()
	be.trackURL = "user-1/run-1.json.gz"
	be.trackByPath["user-1/run-1.json.gz"] = []TrackPoint{
		{Lat: 1, Lng: 2}, {Lat: 1.001, Lng: 2.001},
	}
	// Make DownloadTrack block longer than the worker's per-job
	// timeout. The fake's select honours ctx.Done so when
	// HandleTimeout fires the jobCtx cancels and DownloadTrack
	// returns ctx.Err() = context.DeadlineExceeded.
	be.downloadDelay = 200 * time.Millisecond
	be.jobs = []*Job{{
		ID: 42, Kind: "map_match", Attempts: 1,
		Payload: mustPayload(t, MapMatchPayload{RunID: "run-1", UserID: "user-1"}),
	}}

	w := newTestWorker(be, PassthroughMatcher{})
	// 50 ms per-job timeout vs 200 ms download delay → timeout
	// always fires first.
	w.Config.HandleTimeout = 50 * time.Millisecond

	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if len(be.finished) != 0 {
		t.Errorf(
			"timeout was finish_job'd (should defer for retry): %+v",
			be.finished,
		)
	}
	if len(be.deferred) != 1 {
		t.Fatalf(
			"expected exactly 1 defer_job call (the timeout path); got %d: %+v",
			len(be.deferred), be.deferred,
		)
	}
	if be.deferred[0].JobID != 42 {
		t.Errorf("deferred job_id=%d, want 42", be.deferred[0].JobID)
	}
	if be.deferred[0].DelayS != 5 {
		t.Errorf(
			"deferred delay_s=%d, want 5 (TransientDelay default in newTestWorker)",
			be.deferred[0].DelayS,
		)
	}
	if be.deferred[0].ErrMsg == nil ||
		!strings.Contains(strings.ToLower(*be.deferred[0].ErrMsg), "deadline") {
		t.Errorf(
			"defer error msg should mention deadline; got %v",
			be.deferred[0].ErrMsg,
		)
	}
}

// ---- helpers -----------------------------------------------------------

func keys[K comparable, V any](m map[K]V) []K {
	out := make([]K, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

// ---- token_refresh -----------------------------------------------------

// newTokenRefreshWorker wires a worker with the token-refresh deps. The
// dispatcher still calls handleMapMatch for any map_match job, but the
// happy path here only enqueues `token_refresh`, so the matcher arg is
// nil to make it obvious if a misrouted job tries to use it.
func newTokenRefreshWorker(be Backend, st StravaIngestor) *Worker {
	w := newTestWorker(be, nil)
	w.Strava = st
	return w
}

func TestTokenRefresh_NoExpiringIsNoop(t *testing.T) {
	be := newFakeBackend()
	st := &fakeStrava{}
	be.jobs = []*Job{{ID: 1, Kind: "token_refresh", Attempts: 1, Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 {
		t.Fatalf("finished=%d, want 1", got)
	}
	if be.finished[0].Status != "done" {
		t.Errorf("status=%q, want done", be.finished[0].Status)
	}
	if got := len(st.calls); got != 0 {
		t.Errorf("strava calls=%d, want 0 (no expiring rows)", got)
	}
	if got, want := len(be.fetchExpiringWindows), 1; got != want {
		t.Fatalf("fetch calls=%d, want %d", got, want)
	}
	if be.fetchExpiringWindows[0] != time.Hour {
		t.Errorf("fetch window=%v, want 1h", be.fetchExpiringWindows[0])
	}
}

func TestTokenRefresh_RotatesEveryExpiringRow(t *testing.T) {
	be := newFakeBackend()
	be.expiring = []IntegrationRow{
		{ID: 1, UserID: "user-A"},
		{ID: 2, UserID: "user-B"},
	}
	be.tokensByUser = map[string]TokenPair{
		"user-A": {AccessToken: "old-A", RefreshToken: "rt-A"},
		"user-B": {AccessToken: "old-B", RefreshToken: "rt-B"},
	}
	expiresAt := time.Now().Add(6 * time.Hour).Unix()
	st := &fakeStrava{
		byToken: map[string]StravaTokenResponse{
			"rt-A": {AccessToken: "new-A", RefreshToken: "rt-A2", ExpiresAt: expiresAt},
			"rt-B": {AccessToken: "new-B", RefreshToken: "rt-B2", ExpiresAt: expiresAt},
		},
	}
	be.jobs = []*Job{{ID: 99, Kind: "token_refresh", Payload: []byte(`{}`)}}

	w := newTokenRefreshWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Fatalf("finished=%v, want one done", be.finished)
	}
	if got := len(st.calls); got != 2 {
		t.Fatalf("strava calls=%d, want 2", got)
	}
	if got := len(be.setTokenCalls); got != 2 {
		t.Fatalf("set_integration_tokens calls=%d, want 2", got)
	}
	// Spot-check one rotation: new access + new refresh + correct expiry.
	for _, c := range be.setTokenCalls {
		if c.Provider != "strava" {
			t.Errorf("provider=%q, want strava", c.Provider)
		}
		if c.AccessToken == "" || c.RefreshToken == "" {
			t.Errorf("set with empty tokens: %+v", c)
		}
		if c.Expiry.Unix() != expiresAt {
			t.Errorf("expiry=%v, want %v", c.Expiry.Unix(), expiresAt)
		}
	}
}

func TestTokenRefresh_SkipsRowWithoutVaultToken(t *testing.T) {
	be := newFakeBackend()
	be.expiring = []IntegrationRow{{ID: 1, UserID: "ghost"}}
	// tokensByUser empty → GetIntegrationTokens returns (nil, nil) for any user.
	st := &fakeStrava{}
	be.jobs = []*Job{{ID: 1, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Fatalf("job must still finish done even when all rows are skipped; got %v", be.finished)
	}
	if got := len(st.calls); got != 0 {
		t.Errorf("strava calls=%d, want 0 (no token to send)", got)
	}
	if got := len(be.setTokenCalls); got != 0 {
		t.Errorf("set calls=%d, want 0", got)
	}
}

func TestTokenRefresh_StravaErrorOnOneRowSkipsButContinues(t *testing.T) {
	be := newFakeBackend()
	be.expiring = []IntegrationRow{
		{ID: 1, UserID: "alice"},
		{ID: 2, UserID: "bob"},
	}
	be.tokensByUser = map[string]TokenPair{
		"alice": {RefreshToken: "rt-alice"},
		"bob":   {RefreshToken: "rt-bob"},
	}
	expiresAt := time.Now().Add(6 * time.Hour).Unix()
	st := &fakeStrava{
		byToken: map[string]StravaTokenResponse{
			"rt-bob": {AccessToken: "new-bob", RefreshToken: "rt-bob2", ExpiresAt: expiresAt},
		},
		errsByToken: map[string]error{
			"rt-alice": &HTTPError{StatusCode: 400, Body: "invalid_grant"},
		},
	}
	be.jobs = []*Job{{ID: 5, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Fatalf("job must still finish done; one row's permanent skip shouldn't fail the whole sweep. got %v", be.finished)
	}
	if got := len(be.setTokenCalls); got != 1 {
		t.Fatalf("set calls=%d, want 1 (only bob)", got)
	}
	if be.setTokenCalls[0].UserID != "bob" {
		t.Errorf("rotated user=%q, want bob", be.setTokenCalls[0].UserID)
	}
	// /audit/strava High #2 — the 4xx alice row gets stamped as
	// disconnected so the next sweep doesn't pick her up forever.
	if got := len(be.markDisconnectedCalls); got != 1 {
		t.Fatalf("mark-disconnected calls=%d, want 1 (alice)", got)
	}
	if be.markDisconnectedCalls[0].UserID != "alice" {
		t.Errorf("marked user=%q, want alice", be.markDisconnectedCalls[0].UserID)
	}
	if be.markDisconnectedCalls[0].Reason != "invalid_grant" {
		t.Errorf("reason=%q, want invalid_grant", be.markDisconnectedCalls[0].Reason)
	}
}

func TestTokenRefresh_RefreshesConcurrently(t *testing.T) {
	// Guard for the bounded-concurrency fix: the per-user refreshes must run in
	// parallel (up to refreshConcurrency) so a large sweep's ~1s-each Strava
	// latency overlaps instead of summing past the HandleTimeout. A regression
	// to a serial loop maxes in-flight at 1 and fails the `== refreshConcurrency`
	// assertion (the watcher's deadline still releases the goroutines so the
	// test fails cleanly rather than hanging).
	be := newFakeBackend()
	const n = refreshConcurrency + 5
	rows := make([]IntegrationRow, n)
	tokensByUser := map[string]TokenPair{}
	byToken := map[string]StravaTokenResponse{}
	exp := time.Now().Add(6 * time.Hour).Unix()
	for i := 0; i < n; i++ {
		uid := fmt.Sprintf("u%d", i)
		rt := fmt.Sprintf("rt-%d", i)
		rows[i] = IntegrationRow{ID: int64(i + 1), UserID: uid}
		tokensByUser[uid] = TokenPair{RefreshToken: rt}
		byToken[rt] = StravaTokenResponse{AccessToken: "a", RefreshToken: rt + "2", ExpiresAt: exp}
	}
	be.expiring = rows
	be.tokensByUser = tokensByUser

	var mu sync.Mutex
	inFlight, maxInFlight := 0, 0
	release := make(chan struct{})
	st := &fakeStrava{byToken: byToken}
	st.refreshHook = func() {
		mu.Lock()
		inFlight++
		if inFlight > maxInFlight {
			maxInFlight = inFlight
		}
		mu.Unlock()
		<-release // hold the goroutine so overlap is observable
		mu.Lock()
		inFlight--
		mu.Unlock()
	}

	// Release the held goroutines once the pool saturates at the cap, or after
	// a deadline (so a serial regression completes + fails instead of hanging).
	go func() {
		deadline := time.After(3 * time.Second)
		for {
			mu.Lock()
			cur := maxInFlight
			mu.Unlock()
			if cur >= refreshConcurrency {
				close(release)
				return
			}
			select {
			case <-deadline:
				close(release)
				return
			case <-time.After(5 * time.Millisecond):
			}
		}
	}()

	be.jobs = []*Job{{ID: 1, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = w.Run(ctx)

	if maxInFlight != refreshConcurrency {
		t.Fatalf("max concurrent refreshes=%d, want %d (sweep must fan out, bounded by the pool)",
			maxInFlight, refreshConcurrency)
	}
	if got := len(be.setTokenCalls); got != n {
		t.Fatalf("rotated %d rows, want all %d", got, n)
	}
}

func TestTokenRefresh_5xxIsTransientAndDoesntDisconnect(t *testing.T) {
	// /audit/strava High #5 — a Strava 502 is transient. The row
	// must NOT be marked disconnected (the next sweep should retry).
	be := newFakeBackend()
	be.expiring = []IntegrationRow{{ID: 1, UserID: "carol"}}
	be.tokensByUser = map[string]TokenPair{
		"carol": {RefreshToken: "rt-carol"},
	}
	st := &fakeStrava{
		errsByToken: map[string]error{
			"rt-carol": &HTTPError{StatusCode: 502, Body: "bad gateway"},
		},
	}
	be.jobs = []*Job{{ID: 7, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)
	if got := len(be.markDisconnectedCalls); got != 0 {
		t.Fatalf("5xx must NOT trigger disconnect; got %d marks", got)
	}
	if got := len(be.setTokenCalls); got != 0 {
		t.Fatalf("set calls=%d, want 0", got)
	}
}

func TestTokenRefresh_FetchExpiringErrorFailsJob(t *testing.T) {
	be := newFakeBackend()
	be.fetchExpiringErr = &HTTPError{StatusCode: 500, Body: "boom"}
	st := &fakeStrava{}
	be.jobs = []*Job{{ID: 3, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	// 5xx is transient → defer, not finish.
	if got := len(be.deferred); got != 1 {
		t.Fatalf("deferred=%d, want 1 (5xx is transient)", got)
	}
	if got := len(be.finished); got != 0 {
		t.Errorf("finished=%d, want 0 (job was deferred)", got)
	}
}

func TestTokenRefresh_NoStravaClientFailsPermanent(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{ID: 1, Kind: "token_refresh", Payload: []byte(`{}`)}}
	// Worker.Strava intentionally left nil — simulates an operator who
	// enqueued a token_refresh job without setting the Strava env vars.
	w := newTestWorker(be, nil)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "failed" {
		t.Fatalf("unconfigured worker must surface a permanent failure; got %v", be.finished)
	}
}

func TestTokenRefresh_StravaErrorIsTransient_DeferJob(t *testing.T) {
	be := newFakeBackend()
	be.expiring = []IntegrationRow{{ID: 1, UserID: "alice"}}
	be.tokensByUser = map[string]TokenPair{"alice": {RefreshToken: "rt-alice"}}
	// 5xx from Strava is transient; the row is skipped (job still
	// finishes "done" for the sweep as a whole). Pinned here to
	// document the policy: ONE bad row never fails the sweep.
	st := &fakeStrava{
		errsByToken: map[string]error{
			"rt-alice": &HTTPError{StatusCode: 503, Body: "down"},
		},
	}
	be.jobs = []*Job{{ID: 1, Kind: "token_refresh", Payload: []byte(`{}`)}}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "done" {
		t.Fatalf("one Strava 503 row must skip, not fail the sweep: %v", be.finished)
	}
	if got := len(be.setTokenCalls); got != 0 {
		t.Errorf("set calls=%d, want 0 (rotation failed)", got)
	}
}

func TestTokenRefresh_DispatchUnknownKindIsPermanentFail(t *testing.T) {
	be := newFakeBackend()
	be.jobs = []*Job{{ID: 1, Kind: "some-future-kind", Payload: []byte(`{}`)}}
	st := &fakeStrava{}
	w := newTokenRefreshWorker(be, st)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	_ = w.Run(ctx)

	if got := len(be.finished); got != 1 || be.finished[0].Status != "failed" {
		t.Fatalf("unknown kind must fail permanent; got %v", be.finished)
	}
}
