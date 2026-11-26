package desktop

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"scistation.local/desktop/internal/credentials"
	"scistation.local/desktop/internal/gateway"
)

func setupProviderProfiles(prefs *settingsStore, data, identity string) {
	_, keys, err := credentials.WorkspaceStores(identity)
	if err != nil {
		log.Print("无法为此数据目录启用直接模型钥匙串")
		return
	}
	if keys == nil {
		return
	}
	profiles, err := openProviderProfiles(data, keys)
	if err != nil {
		log.Print("无法读取直接模型配置；现有配置文件已保留")
		return
	}
	prefs.providerProfiles = profiles
}

type providerProfileView struct {
	gateway.CompatibleProfile
	Configured     bool `json:"configured"`
	KeyUnavailable bool `json:"key_unavailable,omitempty"`
}

func (a *apiServer) manageProviderProfiles(w http.ResponseWriter, r *http.Request) {
	if !a.canUseDesktopCredentials(r) {
		reject(w, http.StatusForbidden, "请在 Sci-Station 桌面应用中管理直接模型")
		return
	}
	store := a.prefs.providerProfiles
	if store == nil {
		reject(w, http.StatusServiceUnavailable, "直接模型配置暂不可用，请检查应用数据目录和 macOS 钥匙串")
		return
	}
	switch r.Method {
	case http.MethodGet:
		views := []providerProfileView{}
		for _, p := range store.Profiles() {
			configured, err := store.configured(p)
			views = append(views, providerProfileView{CompatibleProfile: p, Configured: configured, KeyUnavailable: err != nil})
		}
		reply(w, http.StatusOK, views)
	case http.MethodPost:
		a.applyProviderAction(store, w, r)
	default:
		w.Header().Set("Allow", "GET, POST")
		reject(w, http.StatusMethodNotAllowed, "不支持此操作")
	}
}

func (a *apiServer) applyProviderAction(store *providerProfileStore, w http.ResponseWriter, r *http.Request) {
	var input struct {
		Action  string                     `json:"action"`
		ID      string                     `json:"id"`
		Profile *gateway.CompatibleProfile `json:"profile"`
		Key     string                     `json:"key"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	var err error
	key := strings.TrimSpace(input.Key)
	switch {
	case input.Action == "save" && input.Profile != nil && key == "" && input.ID == "":
		var profile gateway.CompatibleProfile
		profile, err = store.upsert(*input.Profile)
		if err == nil {
			reply(w, http.StatusOK, profile)
			return
		}
	case input.Action == "set_key" && input.Profile == nil && validProviderID(input.ID) && validStoredToken(key):
		err = store.updateKey(input.ID, key)
	case input.Action == "clear_key" && input.Profile == nil && validProviderID(input.ID) && key == "":
		err = store.updateKey(input.ID, "")
	case input.Action == "remove" && input.Profile == nil && validProviderID(input.ID) && key == "":
		err = store.remove(input.ID)
	case input.Action == "test" && input.Profile != nil && input.ID == "" && (key == "" || validStoredToken(key)):
		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		defer cancel()
		if err := studioGateway(a.prefs).TestCompatible(ctx, *input.Profile, key); err != nil {
			reject(w, http.StatusBadGateway, err.Error())
			return
		}
	default:
		reject(w, http.StatusBadRequest, "请输入有效的直接模型配置或 API Key")
		return
	}
	if err != nil {
		status := http.StatusBadRequest
		switch {
		case errors.Is(err, errProviderProfileMissing):
			status = http.StatusNotFound
		case errors.Is(err, errProviderKeychain):
			status = http.StatusServiceUnavailable
		case errors.Is(err, errProviderWrite):
			status = http.StatusInternalServerError
		}
		reject(w, status, err.Error())
		return
	}
	reply(w, http.StatusOK, map[string]bool{"ok": true})
}
