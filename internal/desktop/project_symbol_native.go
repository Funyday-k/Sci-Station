//go:build darwin && cgo && !nogui

package desktop

/*
#cgo LDFLAGS: -framework AppKit
#include <stdlib.h>
void *sciProjectSymbol(const char *name, int *length);
*/
import "C"
import "unsafe"

func nativeSymbol(name string) []byte {
	str := C.CString(name)
	defer C.free(unsafe.Pointer(str))
	var count C.int
	bytes := C.sciProjectSymbol(str, &count)
	if bytes == nil {
		return nil
	}
	defer C.free(bytes)
	return C.GoBytes(bytes, count)
}
