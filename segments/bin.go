package segments

import "os"

func init() {
	Register("bin", processBin)
}

func processBin(ctx *Context) (*Result, error) {
	outPath := ctx.SegPath(ctx.AssetDir, ".bin")
	if ctx.DryRun {
		return &Result{Includes: []Include{{Path: outPath, Addr: ctx.Start(), Name: ctx.Seg.Name}}, IsBinary: true}, nil
	}
	if err := ctx.EnsureDir(outPath); err != nil {
		return nil, err
	}
	return &Result{
		Includes: []Include{{Path: outPath, Addr: ctx.Start(), Name: ctx.Seg.Name}},
		IsBinary: true,
	}, os.WriteFile(outPath, ctx.ROMData(), 0644)
}
