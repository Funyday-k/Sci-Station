package desktop

import "golang.org/x/sys/unix"

func renameRootExclusive(fd int, from, to string) error {
	return unix.RenameatxNp(fd, from, fd, to, unix.RENAME_EXCL)
}
