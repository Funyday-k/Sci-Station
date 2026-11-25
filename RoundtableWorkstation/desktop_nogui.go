//go:build !darwin || nogui

package main

import "errors"

func runDesktop(_ string, _ int) error {
	return errors.New("native desktop is unavailable in this build; run with --headless to open the web interface")
}
