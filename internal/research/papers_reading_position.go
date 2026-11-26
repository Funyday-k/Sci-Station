package research

import (
	"fmt"
	"math"
	"net/http"
	"os"
)

// Reading position belongs to the shared PDF. It is independent of project
// membership and of the paper revision used for content edits.
type PDFReadingPosition struct {
	SourceHash string  `json:"sourceHash"`
	Page       int     `json:"page"`
	Zoom       float64 `json:"zoom"`
	Scroll     float64 `json:"scroll"`
}

func (s *PaperLibrary) updatePDFReadingPositionHTTP(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		paperMethod(w, "POST")
		return
	}
	var position PDFReadingPosition
	if err := paperDecode(http.MaxBytesReader(w, r.Body, 4<<10), &position); err != nil {
		paperError(w, err)
		return
	}
	if position.Page < 1 || position.Page > 1000000 ||
		math.IsNaN(position.Zoom) || position.Zoom < 0.55 || position.Zoom > 3 ||
		math.IsNaN(position.Scroll) || position.Scroll < 0 || position.Scroll > 1 {
		paperError(w, fmt.Errorf("%w：阅读位置无效", errInvalidPaper))
		return
	}
	if err := s.savePDFReadingPosition(id, position); err != nil {
		paperError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *PaperLibrary) savePDFReadingPosition(id string, position PDFReadingPosition) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	paper, ok := s.records[id]
	if !ok {
		return os.ErrNotExist
	}
	if !paper.HasPDF || position.SourceHash == "" || position.SourceHash != paper.FileSHA256 {
		return fmt.Errorf("%w：来源 PDF 指纹不同", errPaperConflict)
	}
	if paper.ReadingPosition != nil && position == *paper.ReadingPosition {
		return nil
	}
	paper.ReadingPosition = &position
	return s.saveLocked(paper)
}
