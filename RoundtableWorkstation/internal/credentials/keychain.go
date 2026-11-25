// Package credentials stores app-managed secrets in the macOS Keychain.
package credentials

import (
	"crypto/sha256"
	"fmt"
	"path/filepath"
)

// Store represents the MinerU credential for one workstation data directory.
type Store interface {
	Configured() (bool, error)
	Resolve() (string, error)
	Save(value string) error
	Delete() error
}

// Open scopes the credential to the canonical local data directory. It never
// queries Keychain or inspects legacy settings. Unsupported builds return nil.
func Open(dir string) (Store, error) {
	account, err := accountForDirectory(dir)
	if err != nil {
		return nil, err
	}
	return newKeychain(account), nil
}

func accountForDirectory(dir string) (string, error) {
	absolute, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	canonical, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("mineru:%x", sha256.Sum256([]byte(canonical))), nil
}
