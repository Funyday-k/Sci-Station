package meeting

import (
	"fmt"
	"path/filepath"
	"strings"

	"scistation.local/desktop/internal/deliberation"
	"scistation.local/desktop/internal/workspace"
)

// renderTranscript keeps the saved meeting record readable while retaining the
// established English anchors used by existing exports and consumers.
func renderTranscript(s *Session) string {
	var b strings.Builder
	heading := s.Title
	if heading == "" {
		heading = s.Topic
	}
	fmt.Fprintf(&b, "# %s\n\n", heading)
	if s.Title != "" {
		fmt.Fprintf(&b, "## Task\n\n议题原文：\n\n%s\n\n", s.Topic)
	}
	project := filepath.Base(filepath.Clean(s.Project))
	if s.isGlobal() {
		project = "未关联项目"
	}
	fmt.Fprintf(&b, "Project: %s\n\nStatus: %s（%s）\n", project, s.Status, sessionStatusLabel(s.Status))

	if len(s.Agenda) > 0 {
		b.WriteString("\n## 议程\n")
		for _, item := range s.Agenda {
			fmt.Fprintf(&b, "\n### %s\n\n- 状态：%s（%s）\n- 类型：%s\n- 来源：%s\n", item.Title, item.Status, agendaStatusLabel(item.Status), agendaKindLabel(item.Kind), agendaSourceLabel(item.Source))
			if item.SourceRound > 0 {
				fmt.Fprintf(&b, "- 来源轮次：第 %d 轮\n", item.SourceRound)
			}
			if item.SourceSeat != "" {
				fmt.Fprintf(&b, "- 来源席位：%s\n", item.SourceSeat)
			}
			if item.Reason != "" {
				fmt.Fprintf(&b, "- 原因：%s\n", item.Reason)
			}
			for _, revision := range item.Revisions {
				fmt.Fprintf(&b, "- 修订记录：第 %d 轮，席位 %s；原题：%s；原类型：%s；原因：%s\n", revision.Round, revision.Seat, revision.PreviousTitle, agendaKindLabel(revision.PreviousKind), revision.Reason)
			}
		}
	}

	for _, r := range s.Rounds {
		fmt.Fprintf(&b, "\n## 第 %d 轮 (Round %d)\n", r.Number, r.Number)
		if plan, err := deliberation.Resolve(r.Preset, r.Phase); err == nil && plan.Preset != "work" {
			fmt.Fprintf(&b, "\nMode: %s（模式） · Stage: %s（阶段）\n", plan.Label(), plan.PhaseLabel())
		}
		if r.AgendaItemID != "" {
			if item := s.findAgenda(r.AgendaItemID); item != nil {
				fmt.Fprintf(&b, "\n本轮议程：%s\n", item.Title)
			}
		}
		if r.Auto {
			fmt.Fprintf(&b, "\n持续推进任务：%s\n", r.Note)
		} else if r.Note != "" {
			fmt.Fprintf(&b, "\nUser instruction: %s\n", r.Note)
		}
		writePluginGuidanceNames(&b, r.PluginGuidance)
		for _, turn := range r.Turns {
			model := r.RecordedTurnModel(turn)
			if model == "" {
				model = "未记录"
			}
			fmt.Fprintf(&b, "\n### 席位 %s · 模型 %s\n\nStatus: %s（%s）\n", turn.Seat, model, turn.Status, turnStatusLabel(turn.Status))
			if turn.Text != "" {
				fmt.Fprintf(&b, "\n%s\n", turn.Text)
			}
			if turn.Error != "" {
				fmt.Fprintf(&b, "\n错误：%s\n", turn.Error)
			}
			for _, change := range turn.Changes {
				fmt.Fprintf(&b, "\n模型修改（席位 %s · %s）\n\nChanged: %s\n", turn.Seat, model, change.Path)
				if change.Diff != "" {
					writeTranscriptCode(&b, "diff", change.Diff)
				}
			}
		}
	}

	if len(s.UserChanges) > 0 {
		b.WriteString("\n## 人工保存\n")
		originals := userWriteContents(s.Operations)
		for i, entry := range s.UserChanges {
			fmt.Fprintf(&b, "\n### 第 %d 项 · %s\n", i+1, entry.Change.Path)
			if entry.At != "" {
				fmt.Fprintf(&b, "\n时间：%s\n", entry.At)
			}
			content := originals[changeRecordKey(entry.Change)]
			if content == "" {
				content = entry.Change.Diff
			}
			if content != "" {
				fmt.Fprintf(&b, "\n人工保存后的原始内容：\n")
				writeTranscriptCode(&b, "", content)
			}
			if entry.Change.Diff != "" {
				b.WriteString("\n人工保存变更：\n")
				writeTranscriptCode(&b, "diff", entry.Change.Diff)
			}
		}
	}
	writeUnappliedUserOperations(&b, s.Operations)
	return b.String()
}

type transcriptChangeKey struct{ path, before, after string }

func changeRecordKey(change workspace.Change) transcriptChangeKey {
	return transcriptChangeKey{change.Path, change.Before, change.After}
}

func userWriteContents(operations []Operation) map[transcriptChangeKey]string {
	contents := make(map[transcriptChangeKey]string)
	for _, operation := range operations {
		if operation.Seat == "user" && operation.Status == "applied" && operation.Change != nil && operation.Text != "" {
			key := changeRecordKey(*operation.Change)
			if contents[key] == "" {
				contents[key] = operation.Text
			}
		}
	}
	return contents
}

func writeTranscriptCode(b *strings.Builder, language, content string) {
	fence := "```"
	for strings.Contains(content, fence) {
		fence += "`"
	}
	if language != "" {
		fmt.Fprintf(b, "\n%s%s\n%s", fence, language, content)
	} else {
		fmt.Fprintf(b, "\n%s\n%s", fence, content)
	}
	if !strings.HasSuffix(content, "\n") {
		b.WriteByte('\n')
	}
	fmt.Fprintf(b, "%s\n", fence)
}

func writeUnappliedUserOperations(b *strings.Builder, operations []Operation) {
	var pending []Operation
	for _, operation := range operations {
		if operation.Seat == "user" && operation.Status != "applied" {
			pending = append(pending, operation)
		}
	}
	if len(pending) == 0 {
		return
	}
	b.WriteString("\n## 人工写入记录\n")
	for _, operation := range pending {
		fmt.Fprintf(b, "\n### %s · %s\n\n状态：%s（%s）\n", operation.Path, operation.Status, operation.Status, operationStatusLabel(operation.Status))
		if operation.Error != "" {
			fmt.Fprintf(b, "\n错误：%s\n", operation.Error)
		}
		if operation.Text != "" {
			b.WriteString("\n原始写入内容：\n")
			writeTranscriptCode(b, "", operation.Text)
		}
	}
}

func sessionStatusLabel(status string) string {
	switch status {
	case "ready":
		return "就绪"
	case "running":
		return "进行中"
	case "partial":
		return "部分完成"
	case "failed":
		return "失败"
	case "cancelled":
		return "已取消"
	default:
		return "状态"
	}
}

func agendaStatusLabel(status string) string {
	switch status {
	case "pending":
		return "待讨论"
	case "done":
		return "已完成"
	default:
		return "议程状态"
	}
}

func agendaKindLabel(kind string) string {
	switch kind {
	case "discussion":
		return "讨论"
	case "implementation":
		return "实施"
	default:
		return kind
	}
}

func agendaSourceLabel(source string) string {
	switch source {
	case "host":
		return "主持人"
	case "template":
		return "模板"
	case "discussion":
		return "讨论发言"
	case "chair":
		return "主持人起草"
	case "synthesis":
		return "汇总建议"
	default:
		if source == "" {
			return "未记录"
		}
		return source
	}
}

func turnStatusLabel(status string) string {
	return operationStatusLabel(status)
}

func operationStatusLabel(status string) string {
	switch status {
	case "pending":
		return "待处理"
	case "running":
		return "进行中"
	case "done", "applied":
		return "已完成"
	case "error", "failed":
		return "失败"
	case "unknown":
		return "结果未知"
	default:
		return status
	}
}
