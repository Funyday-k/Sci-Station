package research

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestCitationFormatsFromSharedPaper(t *testing.T) {
	lib := testPaperLib(t)
	paper, _, err := lib.create(PaperMetadata{
		Title: "Study Title", Authors: []string{"Ana Silva", "Bo Ng"}, Year: 2021,
		DOI: "10.1000/fixture", PublicationTitle: "Study Journal", Citekey: "Test2021",
		PDFURL: "https://example.com/file.pdf", Abstract: "Line one\nLine two",
	}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	for format, want := range map[string]string{
		"apa":     "Ana Silva, Bo Ng (2021). Study Title. Study Journal https://doi.org/10.1000/fixture",
		"mla":     `Ana Silva, Bo Ng "Study Title." Study Journal 2021 https://doi.org/10.1000/fixture`,
		"chicago": `Ana Silva, Bo Ng "Study Title." Study Journal 2021 https://doi.org/10.1000/fixture`,
		"ieee":    `Ana Silva, Bo Ng "Study Title," Study Journal 2021 https://doi.org/10.1000/fixture`,
		"ris":     "TY  - JOUR\nTI  - Study Title\nAU  - Ana Silva\nAU  - Bo Ng\nPY  - 2021\nJO  - Study Journal\nDO  - 10.1000/fixture\nUR  - https://example.com/file.pdf\nAB  - Line one Line two\nER  -\n",
		"bibtex":  paperBibtex(paper),
	} {
		response := testPaperRequest(t, lib, http.MethodGet, "/"+paper.ID+"/citation?format="+strings.ToUpper(format), "")
		var result map[string]string
		if response.Code != http.StatusOK || json.Unmarshal(response.Body.Bytes(), &result) != nil ||
			result["format"] != format || result["text"] != want {
			t.Fatalf("%s: %d %s", format, response.Code, response.Body.String())
		}
	}
	response := testPaperRequest(t, lib, http.MethodGet, "/"+paper.ID+"/citation?format=invalid", "")
	if response.Code != http.StatusBadRequest {
		t.Fatal(response.Code, response.Body.String())
	}
}
