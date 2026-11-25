package meeting

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

const (
	materialExtractMaxBytes = 24 << 20
	materialExtractMaxText  = 24 << 10
)

// nativeMaterialExcerpt extracts a bounded, local-only preview from an uploaded material.
// The excerpt is deliberately labeled as partial; unsupported or unreadable inputs return errors.
func nativeMaterialExcerpt(path, mimeType, name string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open material: %w", err)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return "", err
	}
	if st.Size() > materialExtractMaxBytes {
		return "", errors.New("material exceeds 24 MiB extraction limit")
	}
	ext := strings.ToLower(filepath.Ext(name))
	if ext == "" {
		ext = strings.ToLower(filepath.Ext(path))
	}
	mt, _, _ := mime.ParseMediaType(mimeType)
	switch {
	case ext == ".txt" || ext == ".md" || ext == ".csv" || ext == ".log" || strings.HasPrefix(mt, "text/"):
		b, e := io.ReadAll(io.LimitReader(f, materialExtractMaxBytes+1))
		if e != nil {
			return "", e
		}
		if len(b) > materialExtractMaxBytes {
			return "", errors.New("material exceeds extraction limit")
		}
		if !utf8.Valid(b) {
			return "", errors.New("text material is not valid UTF-8")
		}
		return boundedMaterialText(string(b))
	case ext == ".docx" || mt == "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
		return extractDOCX(path)
	case ext == ".pdf" || mt == "application/pdf" || strings.HasPrefix(mt, "image/") || ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".tif" || ext == ".tiff" || ext == ".heic":
		return nativeMaterialVisualExcerpt(path, mt, ext)
	default:
		return "", fmt.Errorf("unsupported material format %q; no content was extracted", ext)
	}
}

func boundedMaterialText(s string) (string, error) {
	s = strings.TrimSpace(strings.ToValidUTF8(s, "�"))
	if s == "" {
		return "", errors.New("no readable text was extracted")
	}
	if len(s) > materialExtractMaxText {
		s = s[:materialExtractMaxText]
		for !utf8.ValidString(s) {
			s = s[:len(s)-1]
		}
		s += "\n[Excerpt truncated at 24 KiB.]"
	}
	return s, nil
}

func extractDOCX(path string) (string, error) {
	z, err := zip.OpenReader(path)
	if err != nil {
		return "", fmt.Errorf("read DOCX package: %w", err)
	}
	defer z.Close()
	var out strings.Builder
	remaining := materialExtractMaxBytes
	for _, f := range z.File {
		if f.Name != "word/document.xml" && !strings.HasPrefix(f.Name, "word/header") && !strings.HasPrefix(f.Name, "word/footer") {
			continue
		}
		r, e := f.Open()
		if e != nil {
			continue
		}
		limit := int64(remaining)
		if limit <= 0 {
			r.Close()
			break
		}
		data, e := io.ReadAll(io.LimitReader(r, limit))
		r.Close()
		if e != nil {
			continue
		}
		remaining -= len(data)
		dec := xml.NewDecoder(bytes.NewReader(data))
		for {
			tok, e := dec.Token()
			if e == io.EOF {
				break
			}
			if e != nil {
				break
			}
			switch t := tok.(type) {
			case xml.StartElement:
				if t.Name.Local == "p" {
					out.WriteByte('\n')
				}
			case xml.CharData:
				out.Write([]byte(t))
			}
		}
		if out.Len() > materialExtractMaxText {
			break
		}
	}
	return boundedMaterialText(out.String())
}
