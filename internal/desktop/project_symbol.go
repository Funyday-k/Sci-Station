package desktop

import (
	"io"
	"net/http"
	"regexp"
	"strings"
)

var validProjectSymbol = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9.-]{0,79}$`)
var portableSymbols = map[string]string{
	"folder":            `<path d="M3 8V5h6l2 2h9v12H3z"/>`,
	"atom":              `<ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(35 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(-35 12 12)"/><circle cx="12" cy="12" r="1"/>`,
	"sparkles":          `<path d="m10 3 2.5 6.5L19 12l-6.5 2.5L10 21l-2.5-6.5L1 12l6.5-2.5zM19 2l1 3 3 1-3 1-1 3-1-3-3-1 3-1z"/>`,
	"books.vertical":    `<path d="M3 3h4v17H3zM9 4h4v16H9zm6 1 4-1 3 15-4 1z"/>`,
	"chart.xyaxis.line": `<path d="M3 3v18h18M6 16l5-6 4 2 6-8"/>`,
	"brain":             `<path d="M12 5c-2-4-7-2-7 2-4 1-3 6-1 7-2 4 2 7 5 6 1 2 3 1 3-1V5zm0 0c2-4 7-2 7 2 4 1 3 6 1 7 2 4-2 7-5 6-1 2-3 1-3-1V5zM5 8l3 2m-4 4h4m11-6-3 2m4 4h-4"/>`,
}

func serveProjectSymbol(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/api/workspace/symbol/")
	if r.Method != http.MethodGet || !validProjectSymbol.MatchString(name) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "private, max-age=3600")
	if img := nativeSymbol(name); len(img) > 0 {
		w.Header().Set("Content-Type", "image/png")
		w.Write(img)
		return
	}
	shape := portableSymbols[name]
	if shape == "" {
		shape = portableSymbols["folder"]
	}
	w.Header().Set("Content-Type", "image/svg+xml")
	_, _ = io.WriteString(w, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.65" stroke-linejoin="round" stroke-linecap="round">`+shape+"</svg>")
}
