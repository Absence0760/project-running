module github.com/Absence0760/project-running/apps/job_worker

// Patch-level floor, not a bare `go 1.26`: CVE-2026-46600 has no fix in the
// 1.25 line at all, so anything below 1.26.6 links a stdlib that cannot be
// patched against it. CI resolves its toolchain from this line.
go 1.26.6

require (
	github.com/alicebob/miniredis/v2 v2.38.0
	github.com/coder/websocket v1.8.15
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/redis/go-redis/v9 v9.22.0
	golang.org/x/image v0.45.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/yuin/gopher-lua v1.1.1 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
)
