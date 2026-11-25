//go:build !darwin || nogui

package main

import "fmt"

func runDesktop(address string, _ *apiServer, _ func()) error {
	return fmt.Errorf("native desktop is unavailable in this build; run with --headless to serve %s", address)
}
