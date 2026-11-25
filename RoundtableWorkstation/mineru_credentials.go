package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"scistation.local/desktop/internal/credentials"
)

const minerCredentialHeader = "X-Sci-Station-Miner-Session"
const minerCredentialUnavailable = "无法访问 macOS 钥匙串，请检查权限后重试。"

type minerCredentials struct {
	store credentials.Store
	proof string
}

func newMinerCredentials(store credentials.Store) *minerCredentials {
	return &minerCredentials{store: store, proof: rand.Text()}
}

// Wails runs this script after each page loads. Only the bundled conversion
// view gets the in-memory proof.
func (a *apiServer) minerCredentialSessionScript(address string) string {
	if a == nil || !a.desktop || a.minerCreds == nil {
		return ""
	}
	appURL, err := url.Parse(address)
	if err != nil {
		return ""
	}
	origin, _ := json.Marshal(appURL.Scheme + "://" + appURL.Host)
	proof, _ := json.Marshal(a.minerCreds.proof)
	return `(() => {
		if (location.origin !== ` + string(origin) + ` ||
			(location.pathname !== "/tools" && location.pathname !== "/static/science-tools.html")) return;
		window.sciStationMinerSession = ` + string(proof) + `;
		window.dispatchEvent(new Event("scistation:miner-session"));
	})()`
}

func (a *apiServer) canUseMinerCredential(r *http.Request) bool {
	return a.desktop && a.minerCreds != nil &&
		subtle.ConstantTimeCompare([]byte(r.Header.Get(minerCredentialHeader)), []byte(a.minerCreds.proof)) == 1
}

func validMinerToken(token string) bool {
	return len(token) > 0 && len(token) <= 4096 && strings.IndexFunc(token, func(r rune) bool {
		return r < '!' || r > '~'
	}) == -1
}

func (a *apiServer) minerCredential(w http.ResponseWriter, r *http.Request) {
	if !a.canUseMinerCredential(r) {
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
		case input.Action == "save" && validMinerToken(token):
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
