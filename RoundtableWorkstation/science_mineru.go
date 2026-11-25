package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"regexp"
	"strings"
	"time"

	"scistation.local/desktop/internal/research"
)

// A token is used only on MinerU's fixed API origin. Signed file URLs receive
// neither the token nor local metadata. Conversion begins on explicit upload.
var minerBatchID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

type minerReply struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data struct {
		Batch   string   `json:"batch_id"`
		Files   []string `json:"file_urls"`
		Results []struct {
			DataID string `json:"data_id"`
			Name   string `json:"file_name"`
			State  string `json:"state"`
			ZipURL string `json:"full_zip_url"`
		} `json:"extract_result"`
	} `json:"data"`
}

func minerAPI(ctx context.Context, token, method, suffix string, in any) (minerReply, error) {
	var result minerReply
	var reader io.Reader
	if in != nil {
		b, e := json.Marshal(in)
		if e != nil {
			return result, e
		}
		reader = bytes.NewReader(b)
	}
	req, e := http.NewRequestWithContext(ctx, method, "https://mineru.net/api/v4/"+suffix, reader)
	if e != nil {
		return result, e
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	res, e := scientificHTTP.Do(req)
	if e != nil {
		return result, errors.New("无法连接 MinerU")
	}
	defer res.Body.Close()
	if res.StatusCode/100 != 2 {
		return result, fmt.Errorf("MinerU 返回 HTTP %d", res.StatusCode)
	}
	if e = json.NewDecoder(io.LimitReader(res.Body, 2<<20)).Decode(&result); e != nil {
		return result, errors.New("MinerU 的响应无法解析")
	}
	if result.Code != 0 {
		return result, fmt.Errorf("MinerU 返回错误码 %d", result.Code)
	}
	return result, nil
}
func trustedMinerFile(raw string) bool {
	u, e := url.Parse(raw)
	if e != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" {
		return false
	}
	for _, suffix := range []string{"mineru.net", "aliyuncs.com", "openxlab.org.cn", "openxlab.com", "amazonaws.com", "mineru.org.cn"} {
		if u.Hostname() == suffix || strings.HasSuffix(u.Hostname(), "."+suffix) {
			return true
		}
	}
	return false
}
func (a *apiServer) mineruTool(lab *research.Service, w http.ResponseWriter, r *http.Request, route string) {
	if r.Method != "POST" {
		reject(w, 405, "请使用转换工具")
		return
	}
	var input struct {
		Paper string `json:"paper"`
		Token string `json:"token"`
		Batch string `json:"batch"`
	}
	if !jsonBody(w, r, &input) {
		return
	}
	if route != "mineru/start" && !minerBatchID.MatchString(input.Batch) {
		reject(w, 400, "任务编号无效")
		return
	}
	pdf, e := lab.PaperPDFPath(input.Paper)
	if e != nil {
		reject(w, 404, "论文缺少本地 PDF")
		return
	}
	token := strings.TrimSpace(input.Token)
	if token == "" && a.canUseDesktopCredentials(r) {
		token, e = a.minerCreds.store.Resolve()
		if e != nil {
			reject(w, http.StatusServiceUnavailable, minerCredentialUnavailable)
			return
		}
	}
	if !validStoredToken(token) {
		reject(w, 400, "请输入 MinerU Token 或在桌面应用中保存后重试。")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()
	if route == "mineru/start" {
		file, e := os.Open(pdf)
		if e != nil {
			reject(w, 404, "无法读取 PDF")
			return
		}
		defer file.Close()
		st, e := file.Stat()
		if e != nil || st.Size() > 200<<20 {
			reject(w, 400, "MinerU 上传上限为 200 MiB")
			return
		}
		res, e := minerAPI(ctx, token, "POST", "file-urls/batch", map[string]any{"files": []map[string]string{{"name": input.Paper + ".pdf", "data_id": input.Paper}}, "model_version": "vlm", "enable_formula": true, "enable_table": true})
		if e != nil {
			reject(w, 502, e.Error())
			return
		}
		if !minerBatchID.MatchString(res.Data.Batch) || len(res.Data.Files) != 1 || !trustedMinerFile(res.Data.Files[0]) {
			reject(w, 502, "MinerU 返回的上传地址无效")
			return
		}
		req, e := http.NewRequestWithContext(ctx, "PUT", res.Data.Files[0], file)
		if e != nil {
			reject(w, 502, "上传地址格式无效")
			return
		}
		req.ContentLength = st.Size()
		put, e := scientificHTTP.Do(req)
		if e != nil {
			reject(w, 502, "上传至 MinerU 失败")
			return
		}
		put.Body.Close()
		if put.StatusCode/100 != 2 {
			reject(w, 502, fmt.Sprintf("MinerU 上传返回 HTTP %d", put.StatusCode))
			return
		}
		reply(w, 201, map[string]string{"batch": res.Data.Batch})
		return
	}
	res, e := minerAPI(ctx, token, "GET", "extract-results/batch/"+input.Batch, nil)
	if e != nil {
		reject(w, 502, e.Error())
		return
	}
	for _, item := range res.Data.Results {
		if item.DataID != input.Paper && item.Name != input.Paper+".pdf" {
			continue
		}
		switch item.State {
		case "failed":
			reject(w, 422, "MinerU 转换失败，请在 MinerU 中查看错误详情。")
			return
		case "pending", "running", "converting", "waiting-file":
			reply(w, 200, map[string]string{"state": item.State})
			return
		case "done":
		default:
			reply(w, 200, map[string]string{"state": "pending"})
			return
		}
		if route == "mineru/status" {
			reply(w, 200, map[string]string{"state": "done"})
			return
		}
		if !trustedMinerFile(item.ZipURL) {
			reject(w, 502, "MinerU 结果地址无效")
			return
		}
		req, e := http.NewRequestWithContext(ctx, "GET", item.ZipURL, nil)
		if e != nil {
			reject(w, 502, "MinerU 结果地址无效")
			return
		}
		remote, e := scientificHTTP.Do(req)
		if e != nil {
			reject(w, 502, "无法下载转换结果")
			return
		}
		defer remote.Body.Close()
		if remote.StatusCode/100 != 2 {
			reject(w, 502, "结果尚不可下载")
			return
		}
		read, e := io.ReadAll(io.LimitReader(remote.Body, (64<<20)+1))
		if e != nil || len(read) > 64<<20 {
			reject(w, 413, "转换包超出 64 MiB 或下载中断")
			return
		}
		if r.URL.Query().Get("format") == "zip" {
			w.Header().Set("Content-Type", "application/zip")
			w.Header().Set("Content-Disposition", `attachment; filename="mineru-result.zip"`)
			w.Write(read)
			return
		}
		body, e := markdownFromZip(read)
		if e != nil {
			reject(w, 422, e.Error())
			return
		}
		reply(w, 200, map[string]string{"state": "done", "markdown": body})
		return
	}
	reply(w, 200, map[string]string{"state": "pending"})
}
func markdownFromZip(b []byte) (string, error) {
	z, e := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if e != nil {
		return "", errors.New("转换包损坏")
	}
	var candidate *zip.File
	for _, f := range z.File {
		if !f.FileInfo().IsDir() && strings.EqualFold(path.Ext(f.Name), ".md") && (candidate == nil || path.Base(f.Name) == "full.md") {
			candidate = f
		}
	}
	if candidate == nil {
		return "", errors.New("转换结果没有 Markdown")
	}
	f, e := candidate.Open()
	if e != nil {
		return "", e
	}
	defer f.Close()
	v, e := io.ReadAll(io.LimitReader(f, (8<<20)+1))
	if e != nil || len(v) > 8<<20 {
		return "", errors.New("Markdown 超过 8 MiB 或结果损坏")
	}
	return string(v), nil
}
