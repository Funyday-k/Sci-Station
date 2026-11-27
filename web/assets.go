// Package web provides the embedded workstation interface.
package web

import "embed"

// Assets contains the templates and files served under /static/.
//
//go:embed static/*
var Assets embed.FS

// ReadAsset serves the standalone chooser with the same theme and appearance
// code as the workspace. Each welcome asset is one request on its rootless origin.
func ReadAsset(name string) ([]byte, error) {
	var theme, setup string
	switch name {
	case "static/workspace-welcome.css":
		theme, setup = "static/tokens.css", "static/workspace-setup.css"
	case "static/workspace-welcome.js":
		theme, setup = "static/appearance.js", "static/workspace-setup.js"
	default:
		return Assets.ReadFile(name)
	}
	prefix, err := Assets.ReadFile(theme)
	if err != nil {
		return nil, err
	}
	body, err := Assets.ReadFile(setup)
	if err != nil {
		return nil, err
	}
	return append(append(prefix, '\n'), body...), nil
}
