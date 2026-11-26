package plugins

import (
	"embed"
	"io/fs"
)

//go:embed builtin/*.json
var builtinCatalog embed.FS

func builtinFiles() fs.FS {
	files, err := fs.Sub(builtinCatalog, "builtin")
	if err != nil {
		panic(err)
	}
	return files
}
