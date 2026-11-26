//go:build !darwin || !cgo || nogui

package desktop

func nativeSymbol(string) []byte { return nil }
