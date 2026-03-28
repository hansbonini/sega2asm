package segments

import (
	"os"
	"strings"
)

func init() {
	Register("text", processText)
}

func processText(ctx *Context) (*Result, error) {
	outPath := ctx.SegPath(ctx.AssetDir, ".txt")
	if ctx.DryRun {
		return &Result{Includes: []Include{{Path: outPath, Name: ctx.Seg.Name}}}, nil
	}
	if err := ctx.EnsureDir(outPath); err != nil {
		return nil, err
	}

	data := ctx.ROMData()
	var out string
	if !ctx.Charmap.Empty() {
		out = ctx.Charmap.DecodeString(data, 0x00)
	} else {
		out = strings.Map(func(r rune) rune {
			if r >= 0x20 && r < 0x7F {
				return r
			}
			return '.'
		}, string(data))
	}
	return &Result{
		Includes: []Include{{Path: outPath, Name: ctx.Seg.Name}},
	}, os.WriteFile(outPath, []byte(out), 0644)
}
