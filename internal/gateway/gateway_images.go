package gateway

import (
	"encoding/base64"
	"errors"
	"strings"
)

// InputImage is a local, decoded preview paired with its meeting reference.
type InputImage struct {
	MaterialID string
	MIME       string
	Data       []byte
}

type wireImage struct {
	materialID string
	dataURL    string
}

func makeWireImages(images []InputImage) []wireImage {
	var result []wireImage
	for _, image := range images {
		result = append(result, wireImage{
			materialID: image.MaterialID,
			dataURL:    "data:" + image.MIME + ";base64," + base64.StdEncoding.EncodeToString(image.Data),
		})
	}
	return result
}

// Only the final user message carries the previews. Instructions and earlier
// content retain their existing wire format.
func imageMessages(messages []message, images []wireImage, responses bool) []any {
	encoded := make([]any, 0, len(messages))
	for i, m := range messages {
		if i != len(messages)-1 || m.Role != "user" {
			encoded = append(encoded, m)
			continue
		}
		textType := "text"
		if responses {
			textType = "input_text"
		}
		parts := []map[string]any{{"type": textType, "text": m.Content}}
		for _, image := range images {
			parts = append(parts, map[string]any{"type": textType, "text": "Image preview for material ID " + image.materialID})
			if responses {
				parts = append(parts, map[string]any{"type": "input_image", "image_url": image.dataURL, "detail": "auto"})
			} else {
				parts = append(parts, map[string]any{"type": "image_url", "image_url": map[string]string{"url": image.dataURL}})
			}
		}
		encoded = append(encoded, map[string]any{"role": "user", "content": parts})
	}
	return encoded
}

const imageUnavailable = "\n\nAPPLICATION INPUT AVAILABILITY: Image previews are unavailable for this model request. Use any listed text excerpts and report any visual evidence needed to complete the task."

var errImageInputUnsupported = errors.New("Magpie 模型不支持图片输入。")

func imageInputUnsupported(event map[string]any) bool {
	for _, entry := range []any{event, event["error"], obj(event["response"])["error"]} {
		details := obj(entry)
		switch strings.ToLower(str(details["code"])) {
		case "image_input_not_supported", "input_image_not_supported", "unsupported_image_input", "vision_not_supported":
			return true
		}
		msg := strings.ToLower(str(details["message"]) + str(entry))
		if strings.Contains(msg, "only supports text") || strings.Contains(msg, "text-only model") {
			return true
		}
		for _, phrase := range []string{
			"not support image", "not support input image", "not support vision",
			"image input is not supported", "image inputs are not supported", "images are not supported",
			"unsupported image input", "unsupported input modality: image", "unsupported content type: image",
			"image_url is only supported", "input_image is only supported",
		} {
			if strings.Contains(msg, phrase) {
				return true
			}
		}
		if strings.Contains(msg, "supported values are 'text'") && strings.Contains(msg, "image_url") {
			return true
		}
	}
	return false
}
