package workspace

// PreviewDiff renders the same complete diff used by Write, without writing a file.
func PreviewDiff(path, before, after string) (string, error) {
	clean, err := cleanPath(path)
	if err != nil {
		return "", err
	}
	if !validText([]byte(before)) || !validText([]byte(after)) {
		return "", invalid("file preview must be UTF-8 text within 2 MiB")
	}
	return unifiedDiff(clean, before, after)
}
