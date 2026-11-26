package research

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

const (
	maxMinerArchive   = 64 << 20
	maxMinerEntries   = 8192
	maxFigureBytes    = 12 << 20
	maxPaperImages    = 48 << 20
	maxFigureManifest = 256 << 10
	maxFigurePixels   = 24_000_000
)

type paperAsset struct {
	SHA256 string `json:"sha256"`
	Type   string `json:"media_type"`
	Size   int    `json:"bytes"`
}

type paperAssets struct {
	files    map[string][]byte
	manifest map[string]paperAsset
	index    []byte
}

type MinerMarkdown struct {
	Markdown   string      `json:"markdown"`
	SHA256     string      `json:"sha256"`
	AssetsHash string      `json:"assetsSha256,omitempty"`
	Quality    BodyQuality `json:"quality"`
	assets     paperAssets
}

func hashPaperBytes(b []byte) string {
	hash := sha256.Sum256(b)
	return hex.EncodeToString(hash[:])
}

func validPaperHash(s string) bool {
	_, err := hex.DecodeString(s)
	return len(s) == sha256.Size*2 && err == nil && s == strings.ToLower(s)
}

func archiveEntry(f *zip.File) (string, bool) {
	name := strings.TrimPrefix(f.Name, "./")
	if !f.Mode().IsRegular() || len(name) > 2048 || !fs.ValidPath(name) || name == "." ||
		strings.ContainsAny(name, "\\:") || strings.IndexFunc(name, unicode.IsControl) >= 0 {
		return "", false
	}
	return name, true
}

func archiveFile(f *zip.File, limit int) ([]byte, error) {
	if limit < 0 || f.UncompressedSize64 > uint64(limit) {
		return nil, fmt.Errorf("超出解压大小限制")
	}
	reader, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	data, err := io.ReadAll(io.LimitReader(reader, int64(limit)+1))
	if err != nil || len(data) > limit || uint64(len(data)) != f.UncompressedSize64 {
		return nil, errors.New("条目损坏或超出解压大小限制")
	}
	return data, nil
}

func selectMinerMarkdown(entries map[string]*zip.File) (string, error) {
	if entries["full.md"] != nil {
		return "full.md", nil
	}
	best := ""
	rank, tied := 0, false
	for name := range entries {
		if !strings.EqualFold(path.Ext(name), ".md") {
			continue
		}
		score := 1
		if strings.EqualFold(path.Base(name), "full.md") {
			score = 2
		}
		if score > rank {
			best, rank, tied = name, score, false
		} else if score == rank {
			tied = true
		}
	}
	switch {
	case best == "":
		return "", errors.New("转换结果没有 Markdown")
	case tied:
		return "", errors.New("转换结果含有多个 Markdown，无法确定对应正文")
	default:
		return best, nil
	}
}

// ReadMinerMarkdown keeps the provider's Markdown byte-for-byte. Only local
// raster images referenced by that Markdown are eligible for adoption.
func ReadMinerMarkdown(b []byte) (MinerMarkdown, error) {
	var out MinerMarkdown
	if len(b) > maxMinerArchive {
		return out, errors.New("转换包超出 64 MiB")
	}
	z, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil && !errors.Is(err, zip.ErrInsecurePath) {
		return out, errors.New("转换包损坏")
	}
	if len(z.File) > maxMinerEntries {
		return out, errors.New("转换包包含过多条目")
	}
	entries := make(map[string]*zip.File, len(z.File))
	for _, f := range z.File {
		name, ok := archiveEntry(f)
		if !ok {
			continue
		}
		if entries[name] != nil {
			return out, errors.New("转换包包含同名文件")
		}
		entries[name] = f
	}
	name, err := selectMinerMarkdown(entries)
	if err != nil {
		return out, err
	}
	raw, err := archiveFile(entries[name], 8<<20)
	if err != nil || !utf8.Valid(raw) || bytes.IndexByte(raw, 0) >= 0 {
		return out, errors.New("Markdown 超过 8 MiB 或结果损坏")
	}
	out.Markdown, out.SHA256 = string(raw), hashPaperBytes(raw)
	out.Quality = inspectPaperBody(normalizeWorkflowText(out.Markdown), "mineru")
	a := paperAssets{files: map[string][]byte{}, manifest: map[string]paperAsset{}}
	type checkedAsset struct {
		file  []byte
		entry paperAsset
	}
	checked := make(map[string]checkedAsset)
	budget := maxPaperImages
	for _, figure := range out.Quality.Figures {
		ref := figure.localReference
		resolved := path.Join(path.Dir(name), ref)
		if ref == "" || !fs.ValidPath(resolved) || resolved == "." || entries[resolved] == nil {
			continue
		}
		item, found := checked[resolved]
		if !found {
			file, readErr := archiveFile(entries[resolved], min(budget, maxFigureBytes))
			if readErr != nil {
				return MinerMarkdown{}, fmt.Errorf("引用的转换包图片无法解压或超出限制：%s", figureText(ref, 200))
			}
			budget -= len(file)
			media := safePaperImage(file)
			if media != "" {
				item = checkedAsset{file: file, entry: paperAsset{hashPaperBytes(file), media, len(file)}}
			}
			checked[resolved] = item
		}
		if item.file != nil {
			// The canonical reference is independent of the ZIP's layout.
			id := figureAssetID(ref)
			a.files[id], a.manifest[id] = item.file, item.entry
		}
	}
	out.Quality.attachAssets(a.manifest)
	if len(a.manifest) != 0 {
		var size int
		for _, item := range a.manifest {
			size += item.Size
			if size > maxPaperImages {
				return MinerMarkdown{}, errors.New("引用的转换包图片超出 48 MiB")
			}
		}
		a.index, err = json.Marshal(a.manifest)
		if err != nil || len(a.index) > maxFigureManifest {
			return MinerMarkdown{}, errors.New("无法生成正文图片目录")
		}
		out.AssetsHash = hashPaperBytes(a.index)
		out.assets = a
	}
	return out, nil
}

func knownPaperImage(t string) bool {
	return t == "image/png" || t == "image/jpeg" || t == "image/gif" || t == "image/webp"
}

func safePaperImage(b []byte) string {
	t := http.DetectContentType(b)
	if !knownPaperImage(t) {
		return ""
	}
	var w, h int
	if t == "image/webp" {
		w, h = webPSize(b)
	} else if config, _, err := image.DecodeConfig(bytes.NewReader(b)); err == nil {
		w, h = config.Width, config.Height
	}
	if w <= 0 || h <= 0 || int64(w)*int64(h) > maxFigurePixels {
		return ""
	}
	return t
}

func webPSize(b []byte) (int, int) {
	if len(b) < 25 || uint64(binary.LittleEndian.Uint32(b[4:8]))+8 != uint64(len(b)) ||
		uint64(binary.LittleEndian.Uint32(b[16:20]))+20 > uint64(len(b)) {
		return 0, 0
	}
	switch string(b[12:16]) {
	case "VP8X":
		if len(b) >= 30 && binary.LittleEndian.Uint32(b[16:20]) == 10 {
			return int(b[24]) + int(b[25])<<8 + int(b[26])<<16 + 1, int(b[27]) + int(b[28])<<8 + int(b[29])<<16 + 1
		}
	case "VP8L":
		if b[20] == 0x2f && binary.LittleEndian.Uint32(b[16:20]) >= 5 {
			bits := binary.LittleEndian.Uint32(b[21:25])
			return int(bits&0x3fff) + 1, int(bits>>14&0x3fff) + 1
		}
	case "VP8 ":
		if len(b) >= 30 && binary.LittleEndian.Uint32(b[16:20]) >= 10 && bytes.Equal(b[23:26], []byte{0x9d, 0x01, 0x2a}) {
			return int(binary.LittleEndian.Uint16(b[26:28]) & 0x3fff), int(binary.LittleEndian.Uint16(b[28:30]) & 0x3fff)
		}
	}
	return 0, 0
}

func (s *PaperLibrary) assetPath(id, blob string) string {
	return filepath.Join(s.dir, "markdown", id+"-"+blob+".assets")
}

func (s *PaperLibrary) storeAssets(id, blob string, a paperAssets) error {
	if len(a.index) == 0 {
		return nil
	}
	dst := s.assetPath(id, blob)
	if err := workspace.ManagedMkdir(dst, 0700); err != nil {
		return err
	}
	var err error
	for key, data := range a.files {
		if err = workspace.ManagedAtomicWrite(filepath.Join(dst, key), data); err != nil {
			break
		}
	}
	if err == nil {
		err = workspace.ManagedAtomicWrite(filepath.Join(dst, "index.json"), a.index)
	}
	if err != nil {
		_ = workspace.ManagedRemoveAll(dst)
	}
	return err
}

func readBoundedPaperFile(file string, limit int) ([]byte, error) {
	f, err := workspace.ManagedOpenFile(file, os.O_RDONLY, 0)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, int64(limit)+1))
	if err != nil || len(b) > limit {
		return nil, errors.New("正文图片文件超出限制或无法读取")
	}
	return b, nil
}

func (s *PaperLibrary) assetManifest(p Paper) (map[string]paperAsset, error) {
	m := p.Markdown
	if m == nil || !m.valid() {
		return nil, errInvalidPaper
	}
	if m.AssetsHash == "" {
		return nil, nil
	}
	b, err := readBoundedPaperFile(filepath.Join(s.assetPath(p.ID, m.BlobID), "index.json"), maxFigureManifest)
	if err != nil || hashPaperBytes(b) != m.AssetsHash {
		return nil, errPaperConflict
	}
	var index map[string]paperAsset
	if json.Unmarshal(b, &index) != nil || len(index) < 1 || len(index) > maxPaperFigures {
		return nil, errInvalidPaper
	}
	total := 0
	for id, data := range index {
		if !validPaperHash(id) || !validPaperHash(data.SHA256) || !knownPaperImage(data.Type) || data.Size < 1 || data.Size > maxFigureBytes {
			return nil, errInvalidPaper
		}
		total += data.Size
		if total > maxPaperImages {
			return nil, errInvalidPaper
		}
	}
	return index, nil
}

func (s *PaperLibrary) readPaperAsset(p Paper, id string, item paperAsset) ([]byte, error) {
	b, err := readBoundedPaperFile(filepath.Join(s.assetPath(p.ID, p.Markdown.BlobID), id), item.Size)
	if err != nil || len(b) != item.Size || hashPaperBytes(b) != item.SHA256 || safePaperImage(b) != item.Type {
		return nil, errPaperConflict
	}
	return b, nil
}

func (s *PaperLibrary) verifyPaperAssets(p Paper) error {
	items, err := s.assetManifest(p)
	if err != nil {
		return err
	}
	for id, item := range items {
		if _, err := s.readPaperAsset(p, id, item); err != nil {
			return err
		}
	}
	return nil
}

func (s *PaperLibrary) bodyInspection(p Paper, text string, verifyBytes bool) BodyQuality {
	q := inspectPaperBody(text, p.Markdown.Origin)
	index, err := s.assetManifest(p)
	q.AssetCheckFailed = err != nil
	// Check the full archive in the quality panel. Inline excerpt previews
	// only check presence; the read endpoint verifies each image on display.
	for id, item := range index {
		if verifyBytes {
			if _, err := s.readPaperAsset(p, id, item); err != nil {
				delete(index, id)
			}
			continue
		}
		f, openErr := workspace.ManagedOpenFile(filepath.Join(s.assetPath(p.ID, p.Markdown.BlobID), id), os.O_RDONLY, 0)
		if openErr != nil {
			delete(index, id)
			continue
		}
		stat, statErr := f.Stat()
		f.Close()
		if statErr != nil || stat.Size() != int64(item.Size) {
			delete(index, id)
		}
	}
	q.attachAssets(index)
	return q
}

func (s *PaperLibrary) bodyPreviewHTTP(w http.ResponseWriter, r *http.Request, p Paper) {
	if r.Method != http.MethodGet {
		paperMethod(w, "GET")
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	raw, err := s.readBodyLocked(p)
	if err != nil {
		paperError(w, err)
		return
	}
	text := string(raw)
	w.Header().Set("Cache-Control", "no-store")
	paperReply(w, http.StatusOK, struct {
		Markdown string      `json:"markdown"`
		Hash     string      `json:"hash"`
		Quality  BodyQuality `json:"quality"`
	}{text, p.Markdown.SourceHash(), s.bodyInspection(p, normalizeWorkflowText(text), true)})
}

func (s *PaperLibrary) paperAssetHTTP(w http.ResponseWriter, r *http.Request, p Paper, fingerprint, id string) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		paperMethod(w, "GET, HEAD")
		return
	}
	if !validPaperHash(fingerprint) || !validPaperHash(id) || p.Markdown == nil || p.Markdown.SourceHash() != fingerprint {
		http.NotFound(w, r)
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	// Do not serve from a record revision replaced during the request or by
	// another process. The manifest then binds the image to that revision.
	record, err := workspace.ManagedReadFile(filepath.Join(s.dir, "records", p.ID+".json"))
	if err != nil || sha256.Sum256(record) != p.diskHash {
		paperError(w, errPaperConflict)
		return
	}
	index, err := s.assetManifest(p)
	if err != nil {
		paperError(w, err)
		return
	}
	item, found := index[id]
	if !found {
		http.NotFound(w, r)
		return
	}
	data, err := s.readPaperAsset(p, id, item)
	if err != nil {
		paperError(w, err)
		return
	}
	w.Header().Set("Content-Type", item.Type)
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.Method == http.MethodGet {
		_, _ = w.Write(data)
	}
}
