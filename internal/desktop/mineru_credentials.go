package desktop

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"scistation.local/desktop/internal/credentials"
)

const desktopCredentialHeader = "X-Sci-Station-Credential-Session"
const minerCredentialUnavailable = "无法访问 macOS 钥匙串，请检查权限后重试。"

type minerCredentials struct {
	store       credentials.Store
	proof       string
	labProof    string
	reviewProof string
}

func newMinerCredentials(store credentials.Store) *minerCredentials {
	return &minerCredentials{store: store, proof: rand.Text(), labProof: rand.Text(), reviewProof: rand.Text()}
}

// Wails runs this script after each page loads. Only bundled credential
// management views get the in-memory proof.
func (a *apiServer) desktopCredentialSessionScript(address string) string {
	if a == nil || !a.desktop || a.minerCreds == nil {
		return ""
	}
	appURL, err := url.Parse(address)
	if err != nil {
		return ""
	}
	origin, _ := json.Marshal(appURL.Scheme + "://" + appURL.Host)
	proof, _ := json.Marshal(a.minerCreds.proof)
	labProof, _ := json.Marshal(a.minerCreds.labProof)
	reviewProof, _ := json.Marshal(a.minerCreds.reviewProof)
	return `(() => {
		if (location.origin !== ` + string(origin) + `) return;
		if (["/","/research","/reader","/lab","/studio","/tools","/api-docs"].includes(location.pathname)) {
			window.sciStationConnectorReview = ` + string(reviewProof) + `;
			window.dispatchEvent(new Event("scistation:connector-review"));
		}
		if (["/lab","/static/lab.html"].includes(location.pathname)) {
			window.sciStationConnectorSession = ` + string(labProof) + `;
			window.dispatchEvent(new Event("scistation:connector-session"));
			return;
		}
		if (!["/tools", "/static/science-tools.html", "/studio", "/static/studio.html"].includes(location.pathname)) return;
		window.sciStationCredentialSession = ` + string(proof) + `;
		window.dispatchEvent(new Event("scistation:credential-session"));
	})()`
}

func (a *apiServer) canUseDesktopCredentials(r *http.Request) bool {
	return a.desktop && a.minerCreds != nil &&
		subtle.ConstantTimeCompare([]byte(r.Header.Get(desktopCredentialHeader)), []byte(a.minerCreds.proof)) == 1
}

func validStoredToken(token string) bool {
	return len(token) > 0 && len(token) <= 4096 && strings.IndexFunc(token, func(r rune) bool {
		return r < '!' || r > '~'
	}) == -1
}

func (a *apiServer) minerCredential(w http.ResponseWriter, r *http.Request) {
	if !a.canUseDesktopCredentials(r) {
		reject(w, http.StatusForbidden, "请在 Sci-Station 桌面应用中管理 MinerU Token。")
		return
	}
	var configured bool
	var err error
	switch r.Method {
	case http.MethodGet:
		configured, err = a.minerCreds.store.Configured()
	case http.MethodPost:
		var input struct {
			Action string `json:"action"`
			Token  string `json:"token"`
		}
		if !jsonBody(w, r, &input) {
			return
		}
		token := strings.TrimSpace(input.Token)
		switch {
		case input.Action == "save" && validStoredToken(token):
			err = a.minerCreds.store.Save(token)
			configured = true
		case input.Action == "clear" && token == "":
			err = a.minerCreds.store.Delete()
		default:
			reject(w, http.StatusBadRequest, "请输入有效的 MinerU Token 或选择清除。")
			return
		}
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "不支持此请求")
		return
	}
	if err != nil {
		reject(w, http.StatusServiceUnavailable, minerCredentialUnavailable)
		return
	}
	reply(w, http.StatusOK, map[string]bool{"configured": configured})
}
