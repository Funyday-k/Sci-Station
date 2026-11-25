package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"unicode/utf8"

	"scistation.local/desktop/internal/workspace"
)

type labPreset struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Mode     string `json:"mode"`
	Seats    int    `json:"seats"`
	Prompt   string `json:"prompt"`
	Revision int    `json:"revision"`
	Builtin  bool   `json:"builtin"`
}

var builtInLabPresets = []labPreset{
	{ID: "paper-reading", Title: "单席论文精读", Mode: "review", Seats: 1, Prompt: "围绕给定科研问题精读材料。先概括作者要解决的问题，再逐项核对方法、假设和证据。每项判断标注原文位置，并区分作者结论与读者推论；缺失的材料列为待核查问题。", Revision: 1, Builtin: true},
	{ID: "research-question", Title: "研究问答", Mode: "review", Seats: 1, Prompt: "回答研究问题，明确区分已给出的材料、推断和仍需查证的条件。若问题需要未提供的论文或数据，请指出缺少的依据。", Revision: 1, Builtin: true},
	{ID: "related-work", Title: "相关工作比较", Mode: "review", Seats: 1, Prompt: "围绕研究问题按主题比较所选论文的假设、方法、数据和结果。列出论断、对应的论文和页码、支持强度与不可直接比较的条件。仅使用提供的原文，以证据矩阵总结分歧与待核查问题。", Revision: 1, Builtin: true},
	{ID: "gap-planning", Title: "研究空缺与下一步", Mode: "prioritize", Seats: 1, Prompt: "依据项目笔记、材料和论文摘录，区分已知结果、缺口与推论。对每个候选问题给出来源、可检验假设、对照、所需输入、优先级和完成标准，供研究者审阅后建立任务。", Revision: 1, Builtin: true},
	{ID: "independent-check", Title: "双席独立复核", Mode: "review", Seats: 2, Prompt: "第一席依据提供的材料重建关键推理、推导或数据分析。第二席独立核查适用条件、量纲、边界情形和可重复性。汇总时分别列出双方认可的结果、仍有分歧的判断和能区分它们的下一项检验。", Revision: 1, Builtin: true},
	{ID: "research-design", Title: "多席研究方案评议", Mode: "forum", Seats: 3, Prompt: "围绕研究问题设计可执行的比较。第一席提出物理或实验假设；第二席检视方法、采样与误差；第三席审查可证伪条件与替代解释。形成一份包含变量、对照、观测指标和停止条件的研究计划。", Revision: 1, Builtin: true},
	{ID: "research-priorities", Title: "研究任务排序", Mode: "prioritize", Seats: 2, Prompt: "把给定目标拆为可检验的研究问题。各席分别评估科学收益、依赖、成本和结论不确定性。优先给出能排除关键假设的低成本实验，并为选定的下一步写出验收标准。", Revision: 1, Builtin: true},
}
var labPresetMu sync.Mutex

func listPersonalLabPresets(file string) ([]labPreset, error) {
	b, e := workspace.ManagedReadFile(file)
	if errors.Is(e, os.ErrNotExist) {
		return []labPreset{}, nil
	}
	if e != nil {
		return nil, e
	}
	var rows []labPreset
	if err := json.Unmarshal(b, &rows); err != nil {
		return nil, err
	}
	return rows, nil
}
func validLabPreset(p labPreset) bool {
	return p.Title != "" && utf8.RuneCountInString(p.Title) <= 72 && p.Prompt != "" && utf8.RuneCountInString(p.Prompt) <= 6500 && p.Seats >= 1 && p.Seats <= 4 && slices.Contains([]string{"review", "forum", "prioritize"}, p.Mode)
}
func (a *apiServer) serveAILab(w http.ResponseWriter, r *http.Request) {
	if a.prefs == nil {
		reject(w, 503, "未打开应用设置")
		return
	}
	path := strings.TrimPrefix(r.URL.Path, "/api/research/lab/")
	if strings.HasPrefix(path, "replay/") {
		a.serveLabReplay(w, r, strings.TrimPrefix(path, "replay/"))
		return
	}
	if path == "sources/preview" || path == "sources/prepare" || path == "sources/search" {
		a.serveLabSources(w, r, path)
		return
	}
	if path == "resources/list" || path == "resources/read" {
		serveLabResources(w, r, path)
		return
	}
	pathParts := strings.Split(path, "/")
	if pathParts[0] != "presets" || len(pathParts) > 2 || len(pathParts) == 2 && pathParts[1] == "" {
		http.NotFound(w, r)
		return
	}
	id := ""
	if len(pathParts) == 2 {
		id = pathParts[1]
	}
	if !(r.Method == "GET" && id == "" || r.Method == "POST" && id == "" || r.Method == "PUT" && id != "" || r.Method == "DELETE" && id != "") {
		reject(w, 405, "不支持此请求")
		return
	}
	file := filepath.Join(filepath.Dir(a.prefs.file), "ai-lab-presets.json")
	var edit labPreset
	if r.Method != "GET" {
		if !jsonBody(w, r, &edit) {
			return
		}
		edit.Title = strings.TrimSpace(edit.Title)
		edit.Prompt = strings.TrimSpace(edit.Prompt)
		if r.Method != "DELETE" && !validLabPreset(edit) {
			reject(w, 400, "模板需要名称、1–4 个席位、讨论模式及至多 6,500 字的提示词")
			return
		}
	}
	labPresetMu.Lock()
	defer labPresetMu.Unlock()
	rows, err := listPersonalLabPresets(file)
	if err != nil {
		reject(w, 500, "无法读取个人模板")
		return
	}
	if r.Method == "GET" {
		reply(w, 200, append(slices.Clone(builtInLabPresets), rows...))
		return
	}
	if r.Method == "POST" {
		if len(rows) >= 256 {
			reject(w, 400, "个人模板已达 256 项")
			return
		}
		var bytes [16]byte
		rand.Read(bytes[:])
		edit.ID = hex.EncodeToString(bytes[:])
		edit.Revision = 1
		edit.Builtin = false
		rows = append(rows, edit)
	} else {
		i := slices.IndexFunc(rows, func(p labPreset) bool { return p.ID == id })
		if i < 0 {
			reject(w, 404, "未找到个人模板")
			return
		}
		if edit.Revision != rows[i].Revision {
			reject(w, 409, "此模板已修改，请刷新")
			return
		}
		if r.Method == "DELETE" {
			rows = slices.Delete(rows, i, i+1)
		} else {
			edit.ID = id
			edit.Builtin = false
			edit.Revision++
			rows[i] = edit
		}
	}
	b, e := json.MarshalIndent(rows, "", "  ")
	if e != nil || atomicFile(file, b) != nil {
		reject(w, 500, "个人模板保存失败")
		return
	}
	if r.Method == "DELETE" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	status := http.StatusOK
	if r.Method == "POST" {
		status = http.StatusCreated
	}
	reply(w, status, edit)
}
