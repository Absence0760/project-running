module github.com/Absence0760/project-running/apps/graph_cycle

// Patch-level floor, not a bare `go 1.26`: CVE-2026-46600 has no fix in the
// 1.25 line at all, so anything below 1.26.6 links a stdlib that cannot be
// patched against it. CI resolves its toolchain from this line.
go 1.26.6

require github.com/paulmach/osm v0.9.0

require (
	github.com/DataDog/czlib v0.0.0-20240814115052-86a9592b3985 // indirect
	github.com/paulmach/orb v0.12.0 // indirect
	github.com/paulmach/protoscan v0.2.1 // indirect
	go.mongodb.org/mongo-driver v1.17.7 // indirect
	google.golang.org/protobuf v1.36.10 // indirect
)
