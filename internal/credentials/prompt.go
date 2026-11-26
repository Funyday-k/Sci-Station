package credentials

import (
	"errors"
	"regexp"
)

// Keep this check before persisting a user prompt and before contacting a provider.
var promptSecret = regexp.MustCompile(`(?i)\bsk-[a-z0-9_-]{16,}|gh[pousr]_[a-z0-9_]{20,}|AKIA[0-9A-Z]{16}|eyJ[a-z0-9_-]{12,}\.[a-z0-9_-]{12,}\.[a-z0-9_-]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer[ \t]+[a-z0-9._~-]{16,}`)
var ErrSecretInPrompt = errors.New("内容疑似含有凭据，请移除密钥后重试")

func ContainsSecret(text string) bool {
	return promptSecret.MatchString(text)
}
