//go:build !darwin || !cgo

package credentials

func newKeychain(string) Store { return nil }
