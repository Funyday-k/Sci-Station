package cliedit

// Cursor ACP can request approval for an edit, but the installed agent's own
// policy permits ordinary workspace writes without sending that request.
// Negotiating ACP v1 therefore does not authorize an editable project session.
func CursorAvailable(executable string) (bool, string) {
	if executable == "" {
		return false, "未找到 Cursor CLI"
	}
	return false, "Cursor 可直接写入工作区，无法保证逐项转发审批。可继续只读讨论，或在 Cursor CLI 中编辑。"
}
