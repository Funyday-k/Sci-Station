package desktop

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"net/url"
)

const cliEditHeader = "X-Sci-Station-CLI-Session"

// As for Keychain management, the native window injects a process-local
// capability. Use a separate, rotating value: credentials pages and ordinary
// browsers must not acquire permission to answer a CLI edit request.
func (a *apiServer) cliEditWindowScript(address string) string {
	if a == nil || !a.desktop {
		return ""
	}
	u, err := url.Parse(address)
	if err != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" {
		return ""
	}
	a.cliEdits.windowMu.Lock()
	proof := rand.Text()
	a.cliEdits.windowProof = proof
	a.cliEdits.windowMu.Unlock()
	origin, _ := json.Marshal(u.Scheme + "://" + u.Host)
	encoded, _ := json.Marshal(proof)
	return `(()=>{if(location.origin!==` + string(origin) + `||location.pathname!=="/studio"||window.top!==window)return;window.sciStationCLIEditSession=` + string(encoded) + `;window.dispatchEvent(new Event("scistation:cli-edit-session"));})()`
}
func (a *apiServer) forgetCLIEditWindow() {
	if a == nil {
		return
	}
	a.cliEdits.windowMu.Lock()
	a.cliEdits.windowProof = ""
	a.cliEdits.windowMu.Unlock()
}
func (a *apiServer) authorizedCLIEditWindow(r *http.Request) bool {
	a.cliEdits.windowMu.RLock()
	defer a.cliEdits.windowMu.RUnlock()
	return a.desktop && a.cliEdits.windowProof != "" && subtle.ConstantTimeCompare([]byte(r.Header.Get(cliEditHeader)), []byte(a.cliEdits.windowProof)) == 1
}
