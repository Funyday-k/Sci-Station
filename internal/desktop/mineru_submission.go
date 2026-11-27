package desktop

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"syscall"

	"scistation.local/desktop/internal/research"
)

func minerReceiptError(w http.ResponseWriter) {
	reject(w, http.StatusInternalServerError, "无法读取或保存此论文的 MinerU 本机回执，请检查工作区或恢复已验证的备份。")
}

func minerRecovery(w http.ResponseWriter, r *research.MinerReceipt, message string) {
	reply(w, http.StatusConflict, map[string]string{"error": message, "recovery": r.Attempt, "batch": r.Batch})
}

func minerBatchReply(w http.ResponseWriter, status int, batch, message string) {
	reply(w, status, map[string]string{"batch": batch, "message": message})
}

// A signed upload URL lives only in memory. After a lost PUT response, poll
// the recorded batch before attempting the same upload to its original URL.
func (a *apiServer) startMinerConversion(ctx context.Context, lab *research.Service, w http.ResponseWriter, paper research.Paper, token, suppliedBatch, recovery string) {
	sourceID := minerSourceID(paper.ID, paper.FileSHA256)
	r, err := lab.OpenMinerReceipt(sourceID)
	if errors.Is(err, syscall.EWOULDBLOCK) {
		reject(w, http.StatusConflict, "这篇论文的上传正在进行，请稍后查看。")
		return
	}
	if err != nil {
		minerReceiptError(w)
		return
	}
	defer r.Close()

	if recovery != "" && recovery != r.Attempt {
		reply(w, http.StatusConflict, map[string]string{"error": "任务已更新，请重新查看进度。", "batch": r.Batch})
		return
	}
	if suppliedBatch != "" && suppliedBatch != r.Batch {
		// Users of older workspaces can continue by entering their own batch.
		// Only an exact provider data_id binds it to an outstanding intent.
		if r.State != "batch" {
			res, err := minerAPI(ctx, token, http.MethodGet, "extract-results/batch/"+suppliedBatch, nil)
			if err == nil && res.stateForSource(sourceID) != "" {
				if err := r.RecoverBatch(suppliedBatch); err != nil {
					minerReceiptError(w)
					return
				}
			}
		}
		minerBatchReply(w, http.StatusOK, suppliedBatch, "请用此任务编号查看进度。")
		return
	}
	var uploadURL string
	if r.State == "creating" && recovery != r.Attempt {
		minerRecovery(w, r, "上次建批结果未确认。请先在 MinerU 核对是否已有这篇论文的任务，已有任务可填入编号查看进度。")
		return
	}
	if r.State == "batch" {
		res, err := minerAPI(ctx, token, http.MethodGet, "extract-results/batch/"+r.Batch, nil)
		state := res.stateForSource(sourceID)
		if err == nil && state == "waiting-file" {
			if raw, ok := a.minerUploads.Load(r.Attempt); ok {
				uploadURL = raw.(string)
			}
		}
		var reason string
		switch {
		case err != nil || state == "":
			reason = "已有本机任务编号，但无法核实远端状态。请核对 Token 并在 MinerU 查看该任务。"
		case state == "waiting-file" && uploadURL == "":
			reason = "原任务仍在等待文件，临时上传地址已不可用。请在 MinerU 核对原任务。"
		case state == "failed":
			reason = "MinerU 已将这项任务标为失败。"
		case uploadURL == "":
			a.minerUploads.Delete(r.Attempt)
			minerBatchReply(w, http.StatusOK, r.Batch, "已恢复此前的转换任务，可查看进度。")
			return
		}
		if reason != "" && recovery != r.Attempt {
			minerRecovery(w, r, reason)
			return
		}
	}

	original, pdf, err := lab.ConversionOriginal(ctx, paper.ID)
	if err != nil || original.FileSHA256 != paper.FileSHA256 {
		reject(w, http.StatusUnprocessableEntity, "无法验证本地 PDF")
		return
	}
	if len(pdf) > 200<<20 {
		reject(w, http.StatusBadRequest, "MinerU 上传上限为 200 MiB")
		return
	}
	if uploadURL == "" {
		prior := r.Attempt
		uploadURL = createMinerBatch(ctx, w, r, paper.ID, sourceID, token)
		if uploadURL == "" {
			return
		}
		a.minerUploads.Delete(prior)
		a.minerUploads.Store(r.Attempt, uploadURL)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, uploadURL, bytes.NewReader(pdf))
	if err != nil {
		a.minerUploads.Delete(r.Attempt)
		minerBatchReply(w, http.StatusAccepted, r.Batch, "已建批，但上传地址无效。请在 MinerU 核对该任务。")
		return
	}
	put, err := scientificHTTP.Do(req)
	if err != nil {
		minerBatchReply(w, http.StatusAccepted, r.Batch, "已保留任务编号，上传状态未确认。再次上传会先检查同一任务。")
		return
	}
	put.Body.Close()
	if put.StatusCode/100 != 2 {
		if put.StatusCode == http.StatusForbidden || put.StatusCode == http.StatusGone {
			a.minerUploads.Delete(r.Attempt)
		}
		minerBatchReply(w, http.StatusAccepted, r.Batch, fmt.Sprintf("已保留任务编号，上传返回 HTTP %d。请查看任务进度。", put.StatusCode))
		return
	}
	a.minerUploads.Delete(r.Attempt)
	reply(w, http.StatusCreated, map[string]string{"batch": r.Batch})
}

func createMinerBatch(ctx context.Context, w http.ResponseWriter, r *research.MinerReceipt, paperID, sourceID, token string) string {
	if err := r.Begin(); err != nil {
		minerReceiptError(w)
		return ""
	}
	res, err := minerAPI(ctx, token, http.MethodPost, "file-urls/batch", map[string]any{"files": []map[string]string{{"name": paperID + ".pdf", "data_id": sourceID}}, "model_version": "vlm", "enable_formula": true, "enable_table": true})
	var rejected minerRejection
	if errors.As(err, &rejected) {
		if err := r.Reject(); err != nil {
			minerReceiptError(w)
			return ""
		}
		reject(w, http.StatusBadGateway, err.Error())
		return ""
	}
	if !research.ValidMinerBatchID(res.Data.Batch) {
		reject(w, http.StatusBadGateway, "未能确认是否已建批，请先在 MinerU 核对。已有任务可填入编号查看进度。")
		return ""
	}
	if err := r.RecordBatch(res.Data.Batch); err != nil {
		minerBatchReply(w, http.StatusAccepted, res.Data.Batch, "已建批，但任务编号未能写入本机回执。请保存此编号并在 MinerU 核对。")
		return ""
	}
	if err != nil || len(res.Data.Files) != 1 || !trustedMinerFile(res.Data.Files[0]) {
		minerBatchReply(w, http.StatusAccepted, r.Batch, "已建批，但 MinerU 返回的上传地址无效。请在 MinerU 核对该任务。")
		return ""
	}
	return res.Data.Files[0]
}

func (r minerReply) stateForSource(sourceID string) string {
	for _, item := range r.Data.Results {
		if item.DataID == sourceID {
			return item.State
		}
	}
	return ""
}
