package desktop

import "golang.org/x/sys/unix"

func renameRootExclusive(fd int, from, to string) error {
	return unix.Renameat2(fd, from, fd, to, unix.RENAME_NOREPLACE)
}
