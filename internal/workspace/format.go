package workspace

import (
	"errors"
	"os"
	"path/filepath"
)

// RootMarker and RootFormat identify a workstation that the user explicitly
// created, or an independently restored and verified workstation copy.
const RootMarker = ".sci-station-desktop"
const RootFormat = "sci-station desktop workspace v1\n"

// Find the nearest existing ancestor when a CLI choice still needs creation.
func CheckRootAncestors(path string) error {
	for parent := filepath.Dir(path); ; parent = filepath.Dir(parent) {
		actual, err := filepath.EvalSymlinks(parent)
		if err == nil {
			for current := actual; ; current = filepath.Dir(current) {
				for _, marker := range []string{RootMarker, ".sci-station"} {
					if _, err := os.Lstat(filepath.Join(current, marker)); !os.IsNotExist(err) {
						return errors.New("请选择独立的工作区目录")
					}
				}
				if filepath.Dir(current) == current {
					break
				}
			}
			return nil
		}
		if !os.IsNotExist(err) || parent == filepath.Dir(parent) {
			return err
		}
	}
}
