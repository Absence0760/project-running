package graph

// Thin wrappers so the in-package tests read cleanly; the real construction
// lives in the exported synthetic builders (synthetic.go), shared with the api
// package's tests.

func gridGraph(rows, cols int, spacingM, originLat, originLng float64) *Graph {
	g, _ := BuildTestGrid(rows, cols, spacingM, originLat, originLng)
	return g
}

func lineGraph(n int, spacingM, originLat, originLng float64) *Graph {
	g, _ := BuildTestLine(n, spacingM, originLat, originLng)
	return g
}
