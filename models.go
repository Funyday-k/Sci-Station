package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/gateway"
	"scistation.local/desktop/internal/meeting"
)

// Each operation reads the Magpie-managed connection again; the HTTP transport
// reuses loopback connections across all classic and Studio callers.
func studioGateway(prefs *settingsStore) *gateway.Gateway {
	prefs.gatewayOnce.Do(func() {
		var profiles gateway.CompatibleProfiles
		if prefs.providerProfiles != nil {
			profiles = prefs.providerProfiles
		}
		prefs.gateway = gateway.NewManagedGateway(func() int { return prefs.get().MagpiePort }, profiles)
	})
	return prefs.gateway
}

func (a *apiServer) models(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		reject(w, http.StatusMethodNotAllowed, "请通过 GET 读取模型目录。")
		return
	}
	catalog, err := studioGateway(a.prefs).Catalog(r.Context())
	if err != nil {
		reject(w, http.StatusBadGateway, err.Error())
		return
	}
	reply(w, http.StatusOK, catalog)
}

var errModelCatalog = errors.New("无法读取 Magpie 模型目录")

func (a *apiServer) validateMembers(ctx context.Context, members []meeting.Member) ([]meeting.Member, error) {
	if len(members) == 0 {
		return nil, fmt.Errorf("请选择至少一位参会成员")
	}
	catalog, err := studioGateway(a.prefs).Catalog(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w：%w", errModelCatalog, err)
	}
	models := make(map[string]gateway.Model, len(catalog.Models))
	for _, m := range catalog.Models {
		models[m.ID] = m
	}
	configured := make([]meeting.Member, len(members))
	for i, member := range members {
		seat := "该席位"
		if len(members) > 1 {
			seat = fmt.Sprintf("第 %d 席", i+1)
		}
		model, found := models[member.Model]
		if !found {
			return nil, fmt.Errorf("%s的模型 %q 未列在当前模型目录中", seat, member.Model)
		}
		effort := member.Effort
		if effort == "" {
			effort = "auto"
		}
		if !slices.Contains(model.Efforts, effort) {
			return nil, fmt.Errorf("当前目录未列出%s模型 %q 的思考程度 %q", seat, model.ID, effort)
		}
		configured[i] = meeting.Member{Model: model.ID, Effort: effort, Label: model.Label, Source: model.Source}
	}
	return configured, nil
}

func gatewayCall(g *gateway.Gateway) func(context.Context, string, string, string, string) (string, error) {
	return func(ctx context.Context, seat, model, prompt, _ string) (string, error) {
		model = meeting.CatalogModelID(ctx, seat, model)
		effort, session := meeting.ModelRequest(ctx)
		var images []gateway.InputImage
		for _, m := range meeting.ModelVisualMaterials(ctx) {
			images = append(images, gateway.InputImage{MaterialID: m.ID, MIME: m.MIME, Data: m.Data})
		}
		return g.GenerateWithImages(ctx, model, effort, deliberation.InstructionsFrom(ctx), prompt, session, images, meeting.TextDeltaFromContext(ctx))
	}
}
