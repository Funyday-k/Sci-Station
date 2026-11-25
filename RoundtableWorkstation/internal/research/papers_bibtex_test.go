package research

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
)

func TestProviderBibtexKeyReplacementAndFallback(t *testing.T) {
	const source = `% @book{fake-comment-key, ignored}
@comment{An unpaired " quote and @article{ignored, nested}}
@string{journalAbbreviation = "A@B (journal)"}
@preamble{"Keep this prefix"}
@article ( provider-key % preserve this header comment
, title = "A (quoted) title with \"quotes\"", journal = journalAbbreviation,
  crossref = {provider-key}, custom = {A nested {value} with )}
)`
	lib := testPaperLib(t)
	paper, _, err := lib.create(PaperMetadata{
		Title: "Metadata {value} & $prices$", Authors: []string{"García, Ana"}, Citekey: "Local2026", BibTeX: source,
	}, "", "")
	if err != nil {
		t.Fatal(err)
	}
	path := "/" + paper.ID
	export := testPaperRequest(t, lib, http.MethodGet, path+"/bibtex", "")
	if want := strings.Replace(source, "@article ( provider-key", "@article ( Local2026", 1) + "\n"; export.Code != http.StatusOK || export.Body.String() != want {
		t.Fatalf("provider source changed outside the header: %s", export.Body.String())
	}
	for i, data := range []struct{ source, notice string }{
		{`@misc{first, title={First}} @misc{second, title={Second}}`, "Multiple bibliographic entries"},
		{`@article{provider, title={Truncated}`, "Malformed BibTeX entry"},
		{`@string{journal="A"}`, "No bibliographic entry"},
	} {
		response := testPaperRequest(t, lib, http.MethodPatch, path,
			fmt.Sprintf(`{"revision":%d,"bibtex":%q}`, i+1, data.source))
		if response.Code != http.StatusOK {
			t.Fatal(response.Code, response.Body.String())
		}
		export = testPaperRequest(t, lib, http.MethodGet, path+"/bibtex", "")
		stored, _ := lib.Snapshot(paper.ID)
		if export.Code != http.StatusOK || stored.BibTeX != data.source ||
			!strings.Contains(export.Body.String(), "% Sci-Station: "+data.notice) ||
			!strings.Contains(export.Body.String(), `title = {Metadata \{value\} \& \$prices\$}`) {
			t.Fatal(export.Code, export.Body.String())
		}
	}
}
