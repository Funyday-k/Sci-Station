// prototype-data makes offline backups and isolated restores of the Go desktop prototype.
package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"scistation.local/desktop/internal/workspace"
)

const (
	manifestName = "manifest.json"
	payloadName  = "data"
	processLock  = ".studio-process.lock"
)

type manifest struct {
	Version int                  `json:"version"`
	Source  string               `json:"source"`
	Entries map[string]treeEntry `json:"entries"`
}

const usage = `prototype-data backup -source /absolute/prototype -destination /absolute/new-backup
prototype-data verify -source /absolute/backup
prototype-data restore -source /absolute/backup -destination /absolute/new-recovery-copy
`

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, out io.Writer) error {
	if len(args) == 0 {
		return errors.New(usage)
	}
	if args[0] == "-h" || args[0] == "--help" {
		_, err := fmt.Fprint(out, usage)
		return err
	}
	flags := flag.NewFlagSet(args[0], flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	source := flags.String("source", "", "existing directory")
	destination := flags.String("destination", "", "new directory under an existing parent")
	if err := flags.Parse(args[1:]); err != nil || flags.NArg() != 0 {
		return errors.New(usage)
	}
	var err error
	switch args[0] {
	case "backup":
		err = backup(*source, *destination)
	case "verify":
		if *destination != "" {
			return errors.New(usage)
		}
		var root *os.Root
		root, _, err = openSnapshot(*source)
		if err == nil {
			err = root.Close()
		}
	case "restore":
		err = restore(*source, *destination)
	default:
		return errors.New(usage)
	}
	if err != nil {
		return fmt.Errorf("%s: %w", args[0], err)
	}
	_, err = fmt.Fprintf(out, "%s complete\n", args[0])
	return err
}

func backup(source, destination string) error {
	root, err := openDirectory(source)
	if err != nil {
		return err
	}
	defer root.Close()

	// The prototype uses this inode throughout its lifetime. Open it read-only
	// and never remove it: replacing it could let a live application start.
	guard, err := openRegular(root, processLock, nil)
	if err != nil {
		return fmt.Errorf("expected the prototype's existing process lock: %w", err)
	}
	defer guard.Close()
	if err = syscall.Flock(int(guard.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return fmt.Errorf("cannot take the process lock; quit the prototype and wait for it to exit: %w", err)
	}
	if _, err = root.Lstat(workspace.RootMarker); !errors.Is(err, os.ErrNotExist) {
		return errors.New("source must be a Go prototype directory")
	}

	protected, err := protectedDirectories(root, root.Name())
	if err != nil {
		return err
	}
	return publish(destination, protected, func(stage *os.Root, _ string) error {
		if err := stage.Mkdir(payloadName, 0700); err != nil {
			return err
		}
		payload, err := stage.OpenRoot(payloadName)
		if err != nil {
			return err
		}
		defer payload.Close()
		entries, err := scanTree(root, payload, true)
		if err != nil {
			return err
		}
		if err = verifyTree(payload, entries); err != nil {
			return err
		}
		// The snapshot preserves the source bytes even if a domain record is
		// already damaged. verify and restore check application references.
		data, err := json.MarshalIndent(manifest{Version: 1, Source: root.Name(), Entries: entries}, "", "  ")
		if err != nil {
			return err
		}
		return writePrivate(stage, manifestName, append(data, '\n'))
	})
}

func openSnapshot(path string) (*os.Root, manifest, error) {
	var m manifest
	snapshot, err := openDirectory(path)
	if err != nil {
		return nil, m, err
	}
	defer snapshot.Close()
	if err = readJSON(snapshot, manifestName, &m); err != nil {
		return nil, m, err
	}
	if m.Version != 1 || !absoluteDirectoryName(m.Source) || m.Entries == nil {
		return nil, m, errors.New("unsupported prototype backup manifest")
	}
	payload, err := openSubdirectory(snapshot, payloadName)
	if err != nil {
		return nil, m, err
	}
	if err = verifyTree(payload, m.Entries); err == nil {
		err = validateRecords(payload, m)
	}
	if err != nil {
		payload.Close()
		return nil, m, err
	}
	return payload, m, nil
}

func restore(source, destination string) error {
	payload, m, err := openSnapshot(source)
	if err != nil {
		return err
	}
	defer payload.Close()
	protected, err := protectedDirectories(payload, m.Source)
	if err != nil {
		return err
	}
	protected = append(protected, filepath.Dir(payload.Name()))
	return publish(destination, protected, func(stage *os.Root, finalPath string) error {
		if _, err := scanTree(payload, stage, false); err != nil {
			return err
		}
		if err := verifyTree(stage, m.Entries); err != nil {
			return err
		}
		if err := restorePaths(stage, m, finalPath); err != nil {
			return err
		}
		m.Source = finalPath
		if err := validateRecords(stage, m); err != nil {
			return err
		}
		return writePrivate(stage, workspace.RootMarker, []byte(workspace.RootFormat))
	})
}

func absoluteDirectoryName(path string) bool {
	return filepath.IsAbs(path) && filepath.Clean(path) == path && path != string(filepath.Separator)
}

func within(parent, child string) bool {
	return strings.EqualFold(parent, child) || strings.HasPrefix(strings.ToLower(child), strings.ToLower(parent)+string(filepath.Separator))
}

func openDirectory(path string) (*os.Root, error) {
	if !absoluteDirectoryName(path) {
		return nil, errors.New("give an explicit absolute directory path")
	}
	if err := workspace.CheckRootAncestors(path); err != nil {
		return nil, err
	}
	dir, err := workspace.ManagedOpenDirectory(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	return openSubdirectory(dir, filepath.Base(path))
}

func openSubdirectory(root *os.Root, path string) (*os.Root, error) {
	info, err := root.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%q is not a real directory", path)
	}
	dir, err := root.OpenRoot(path)
	if err != nil {
		return nil, err
	}
	opened, err := dir.Stat(".")
	parentInfo, parentErr := root.Stat(".")
	if err != nil || parentErr != nil || !os.SameFile(info, opened) ||
		info.Sys().(*syscall.Stat_t).Dev != parentInfo.Sys().(*syscall.Stat_t).Dev {
		dir.Close()
		return nil, fmt.Errorf("%q changed while opening", path)
	}
	return dir, nil
}

func publish(path string, sources []string, work func(*os.Root, string) error) error {
	if !absoluteDirectoryName(path) {
		return errors.New("give an explicit absolute destination path")
	}
	if err := workspace.CheckRootAncestors(path); err != nil {
		return err
	}
	dest, err := workspace.ManagedOpenDirectory(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dest.Close()
	name := filepath.Base(path)
	finalPath := filepath.Join(dest.Name(), name)
	for _, source := range sources {
		if within(source, finalPath) || within(finalPath, source) {
			return errors.New("choose a destination separate from the source and linked projects")
		}
	}
	if _, err = dest.Lstat(name); !errors.Is(err, os.ErrNotExist) {
		return errors.New("destination already exists or cannot be checked")
	}
	stageName := ".prototype-data-" + rand.Text()
	if err := dest.Mkdir(stageName, 0700); err != nil {
		return err
	}
	defer dest.RemoveAll(stageName)
	stage, err := openSubdirectory(dest, stageName)
	if err != nil {
		return err
	}
	defer stage.Close()
	if err = work(stage, finalPath); err != nil {
		return err
	}
	if err = syncDirectories(stage); err != nil {
		return err
	}
	parentFile, err := dest.Open(".")
	if err != nil {
		return err
	}
	defer parentFile.Close()
	if err = renameExclusive(int(parentFile.Fd()), stageName, name); err != nil {
		return err
	}
	if err := parentFile.Sync(); err != nil {
		return fmt.Errorf("published verified destination, but could not sync its parent directory: %w", err)
	}
	return nil
}
