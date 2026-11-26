package meeting

import (
	"bytes"
	"context"
	"image"
	"image/jpeg"
	"image/png"
	"io"
)

const (
	maxVisualMaterials    = 4
	maxVisualCandidates   = 8
	maxVisualOriginalSide = 4096
	maxVisualPixels       = 12_000_000
	maxVisualPreviewSide  = 1536
	maxVisualPreviewBytes = 1 << 20
	maxVisualRequestBytes = 3 << 20
)

// VisualMaterial is a decoded, bounded preview for a single model invocation.
// Unlike Material, its payload never belongs to a stored meeting record.
type VisualMaterial struct {
	ID   string
	MIME string
	Data []byte
}

type visualMaterialsKey struct{}

func ModelVisualMaterials(ctx context.Context) []VisualMaterial {
	materials, _ := ctx.Value(visualMaterialsKey{}).([]VisualMaterial)
	return materials
}

func (e *Engine) withVisualMaterials(ctx context.Context, materials []Material) context.Context {
	var previews []VisualMaterial
	remaining, candidates := maxVisualRequestBytes, maxVisualCandidates
	for _, m := range materials {
		if ctx.Err() != nil || len(previews) == maxVisualMaterials || candidates == 0 || remaining == 0 {
			break
		}
		if m.MIME != "image/png" && m.MIME != "image/jpeg" {
			continue
		}
		candidates--
		preview, ok := e.visualPreview(m, min(remaining, maxVisualPreviewBytes))
		if ok {
			previews = append(previews, preview)
			remaining -= len(preview.Data)
		}
	}
	if len(previews) == 0 {
		return ctx
	}
	return context.WithValue(ctx, visualMaterialsKey{}, previews)
}

func (e *Engine) visualPreview(m Material, budget int) (VisualMaterial, bool) {
	if m.Size <= 0 || m.Size > MaxMaterialBytes {
		return VisualMaterial{}, false
	}
	f, err := e.OpenMaterial(m.ID)
	if err != nil {
		return VisualMaterial{}, false
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, MaxMaterialBytes+1))
	if err != nil || int64(len(raw)) != m.Size {
		return VisualMaterial{}, false
	}
	config, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil || config.Width < 1 || config.Height < 1 ||
		config.Width > maxVisualOriginalSide || config.Height > maxVisualOriginalSide ||
		config.Width*config.Height > maxVisualPixels ||
		(format == "png" && m.MIME != "image/png") ||
		(format == "jpeg" && m.MIME != "image/jpeg") ||
		(format != "png" && format != "jpeg") {
		return VisualMaterial{}, false
	}
	original, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return VisualMaterial{}, false
	}
	preview := fitVisualPreview(original)
	var encoded bytes.Buffer
	mime := m.MIME
	if format == "png" {
		err = png.Encode(&encoded, preview)
	} else {
		err = jpeg.Encode(&encoded, preview, &jpeg.Options{Quality: 88})
	}
	if err != nil || encoded.Len() > budget {
		return VisualMaterial{}, false
	}
	return VisualMaterial{ID: m.ID, MIME: mime, Data: encoded.Bytes()}, true
}

func fitVisualPreview(src image.Image) image.Image {
	bounds := src.Bounds()
	width, height := bounds.Dx(), bounds.Dy()
	longest := max(width, height)
	if longest <= maxVisualPreviewSide {
		return src
	}
	w := max(1, width*maxVisualPreviewSide/longest)
	h := max(1, height*maxVisualPreviewSide/longest)
	dst := image.NewNRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			dst.Set(x, y, src.At(bounds.Min.X+x*width/w, bounds.Min.Y+y*height/h))
		}
	}
	return dst
}
