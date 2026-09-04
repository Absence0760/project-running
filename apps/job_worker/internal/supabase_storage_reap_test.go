package internal

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

// The Storage list API is the reaper's only source of an object's age, so the
// walk has to carry `created_at` through — and the name-only projection has to
// stay the same walk, or the paging and the folder descent drift apart.
func TestListStorageObjectsWithMeta_CarriesCreationTimeThroughTheFolderWalk(t *testing.T) {
	var prefixes []string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req struct {
			Prefix string `json:"prefix"`
		}
		_ = json.Unmarshal(body, &req)
		prefixes = append(prefixes, req.Prefix)
		w.Header().Set("Content-Type", "application/json")
		id := "an-id"
		switch req.Prefix {
		case "":
			// A folder: null id, and no created_at of its own.
			_, _ = w.Write([]byte(`[{"name":"u1","id":null}]`))
		case "/u1":
			_, _ = w.Write([]byte(`[{"name":"a.zip","id":"` + id + `","created_at":"2026-01-02T03:04:05Z"},` +
				`{"name":"b.zip","id":"` + id + `"}]`))
		default:
			_, _ = w.Write([]byte(`[]`))
		}
	})

	got, err := client.ListStorageObjectsWithMeta(context.Background(), "exports", "")
	if err != nil {
		t.Fatalf("ListStorageObjectsWithMeta: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %v, want the two objects under the folder", got)
	}
	if got[0].Path != "/u1/a.zip" || !got[0].CreatedAt.Equal(time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)) {
		t.Fatalf("got[0] = %+v", got[0])
	}
	// No `created_at` in the payload must stay zero rather than becoming now:
	// the reaper reads a zero as "age unknown" and skips it.
	if !got[1].CreatedAt.IsZero() {
		t.Fatalf("got[1].CreatedAt = %v, want the zero time for an object the API dated", got[1].CreatedAt)
	}
	if len(prefixes) < 2 {
		t.Fatalf("the folder was not descended into: %v", prefixes)
	}

	names, err := client.ListStorageObjects(context.Background(), "exports", "")
	if err != nil {
		t.Fatalf("ListStorageObjects: %v", err)
	}
	if len(names) != 2 || names[0] != "/u1/a.zip" {
		t.Fatalf("the name-only projection disagrees with the walk: %v", names)
	}
}

func TestDeleteStorageObjects_SendsOneDeleteWithEveryPath(t *testing.T) {
	var method, path, body string
	var auth string
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		method = r.Method
		path = r.URL.Path
		auth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		body = string(raw)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"name":"a.zip"},{"name":"b.zip"}]`))
	})

	if err := client.DeleteStorageObjects(context.Background(), "exports", []string{"u1/a.zip", "u1/b.zip"}); err != nil {
		t.Fatalf("DeleteStorageObjects: %v", err)
	}
	if method != http.MethodDelete {
		t.Fatalf("method = %s, want DELETE — a POST would not erase anything", method)
	}
	if path != "/storage/v1/object/exports" {
		t.Fatalf("path = %s, want the bucket-level multi-delete endpoint", path)
	}
	if !strings.Contains(body, `"prefixes"`) || !strings.Contains(body, "u1/a.zip") ||
		!strings.Contains(body, "u1/b.zip") {
		t.Fatalf("body = %s, want both paths under `prefixes`", body)
	}
	if !strings.Contains(auth, testServiceKey) {
		t.Fatalf("the DELETE went out without the service key: %q", auth)
	}
}

// An empty list must not issue a request at all: a `prefixes: []` body is a
// call whose meaning is up to the server, and there is nothing to erase.
func TestDeleteStorageObjects_EmptyListIssuesNoRequest(t *testing.T) {
	var calls int
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.WriteHeader(http.StatusOK)
	})
	if err := client.DeleteStorageObjects(context.Background(), "exports", nil); err != nil {
		t.Fatalf("DeleteStorageObjects: %v", err)
	}
	if calls != 0 {
		t.Fatalf("calls = %d, want 0", calls)
	}
}

func TestDeleteStorageObjects_ARefusalIsAnError(t *testing.T) {
	client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"error":"not_authorized"}`))
	})
	if err := client.DeleteStorageObjects(context.Background(), "exports", []string{"u1/a.zip"}); err == nil {
		t.Fatal("a 403 from the Storage API must surface — a silently-failed erasure is the bug")
	}
}
