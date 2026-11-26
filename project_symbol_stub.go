//go:build !darwin || !cgo || nogui

package main

func nativeSymbol(string) []byte { return nil }
