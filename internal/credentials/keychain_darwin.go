//go:build darwin && cgo

package credentials

/*
#cgo CFLAGS: -fobjc-arc
#cgo LDFLAGS: -framework Foundation -framework Security
#include <Security/Security.h>
#include <stdlib.h>

OSStatus sciCredentialStatus(const char *account);
OSStatus sciCredentialRead(const char *account, CFDataRef *value);
OSStatus sciCredentialSave(const char *account, const void *bytes, size_t length);
OSStatus sciCredentialDelete(const char *account);
*/
import "C"

import (
	"fmt"
	"unsafe"
)

type keychainStore struct {
	account string
}

func newKeychain(account string) Store { return keychainStore{account: account} }

func (s keychainStore) Configured() (bool, error) {
	account := C.CString(s.account)
	defer C.free(unsafe.Pointer(account))
	status := C.sciCredentialStatus(account)
	return status == C.errSecSuccess, readError(status)
}

func (s keychainStore) Resolve() (string, error) {
	account := C.CString(s.account)
	defer C.free(unsafe.Pointer(account))
	var value C.CFDataRef
	status := C.sciCredentialRead(account, &value)
	if status != C.errSecSuccess {
		return "", readError(status)
	}
	defer C.CFRelease(C.CFTypeRef(value))
	length := C.CFDataGetLength(value)
	if length < 1 || length > 4096 {
		return "", fmt.Errorf("malformed Keychain credential")
	}
	return C.GoStringN((*C.char)(unsafe.Pointer(C.CFDataGetBytePtr(value))), C.int(length)), nil
}

func (s keychainStore) Save(value string) error {
	account := C.CString(s.account)
	defer C.free(unsafe.Pointer(account))
	status := C.sciCredentialSave(account, unsafe.Pointer(unsafe.StringData(value)), C.size_t(len(value)))
	return keychainError(status)
}

func (s keychainStore) Delete() error {
	account := C.CString(s.account)
	defer C.free(unsafe.Pointer(account))
	return readError(C.sciCredentialDelete(account))
}

func readError(status C.OSStatus) error {
	if status == C.errSecItemNotFound {
		return nil
	}
	return keychainError(status)
}

func keychainError(status C.OSStatus) error {
	if status == C.errSecSuccess {
		return nil
	}
	return fmt.Errorf("Keychain operation failed (OSStatus %d)", status)
}
