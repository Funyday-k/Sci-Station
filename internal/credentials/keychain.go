// Package credentials stores app-managed secrets in the macOS Keychain.
package credentials

import (
	"crypto/sha256"
	"encoding/hex"
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

// OpenProviders scopes each key to one workstation, profile, and endpoint.
// Copying the metadata or changing its endpoint cannot carry the key with it.
func OpenProviders(dir string) (func(profileID, endpoint string) Store, error) {
	scope, err := accountForDirectory(dir)
	if err != nil {
		return nil, err
	}
	return providers(scope)
}
func providers(scope string) (func(string, string) Store, error) {
	if newKeychain(scope) == nil {
		return nil, nil
	}
	return func(profileID, endpoint string) Store {
		account := sha256.Sum256([]byte(scope + "\x00" + profileID + "\x00" + endpoint))
		return newKeychain(fmt.Sprintf("llm:%x", account))
	}, nil
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

// WorkspaceStores accepts only an identity resolved by the desktop registry.
// Existing accounts use the same canonical-path digest as Open and OpenProviders.
func WorkspaceStores(identity string) (Store, func(string, string) Store, error) {
	b, err := hex.DecodeString(identity)
	if err != nil || len(b) != sha256.Size {
		return nil, nil, fmt.Errorf("invalid workspace identity")
	}
	account := "mineru:" + identity
	profiles, err := providers(account)
	return newKeychain(account), profiles, err
}
