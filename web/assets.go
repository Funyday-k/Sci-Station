// Package web provides the embedded workstation interface.
package web

import "embed"

// Assets contains the templates and files served under /static/.
//
//go:embed static/*
var Assets embed.FS
