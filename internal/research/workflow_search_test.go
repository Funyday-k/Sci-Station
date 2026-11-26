package research

import (
	"strings"
	"testing"
)

func TestLabSearchOffsetsAndResultLimit(t *testing.T) {
	body := "😀\r\n" + strings.Repeat("Σcan Δ. ", 13)
	r := findWorkflowText(body, "σCAN")
	if !r.Limited || len(r.Items) != 12 || r.Items[0].Offset != 2 || r.Items[1].Offset != 10 {
		t.Fatal(r)
	}
	if result := findWorkflowText(body, "absent"); len(result.Items) != 0 || result.Limited {
		t.Fatal(result)
	}
}
