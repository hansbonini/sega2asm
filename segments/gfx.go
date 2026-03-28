package segments

import (
	"os"

	"sega2asm/compress"
	"sega2asm/types"
	_ "sega2asm/types/gfx"
)

func init() {
	Register("gfx", func(ctx *Context) (*Result, error) { return processGFX(ctx, false) })
	Register("gfxcomp", func(ctx *Context) (*Result, error) { return processGFX(ctx, true) })
}

func processGFX(ctx *Context, compressed bool) (*Result, error) {
	binPath := ctx.SegPath(ctx.AssetDir, ".bin")
	pngPath := ctx.SegPath(ctx.AssetDir, ".png")
	if ctx.DryRun {
		return &Result{Includes: []Include{{Path: binPath, Addr: ctx.Start(), Name: ctx.Seg.Name}}, IsBinary: true}, nil
	}
	if err := ctx.EnsureDir(binPath); err != nil {
		return nil, err
	}

	rawData := ctx.ROMData()

	// Always save original (possibly compressed) bytes for incbin.
	if err := os.WriteFile(binPath, rawData, 0644); err != nil {
		return nil, err
	}

	// Decompress if needed, then render PNG for reference.
	gfxData := rawData
	if compressed {
		dec, err := compress.Decompress(ctx.Seg.Compression, rawData)
		if err != nil {
			ctx.Warn("  decompression failed (%s): %v – PNG skipped", ctx.Seg.Compression, err)
		} else {
			gfxData = dec
			decPath := ctx.SegPath(ctx.AssetDir, ".decompressed.bin")
			if err := os.WriteFile(decPath, gfxData, 0644); err != nil {
				ctx.Warn("  writing decompressed bin failed: %v", err)
			}
		}
	}
	opts := types.GfxOptions{TilesPerRow: 16, Scale: 2, BPP: ctx.Seg.BPP}
	if err := types.DumpTiles(gfxData, pngPath, opts); err != nil {
		ctx.Warn("  PNG render failed: %v", err)
	} else {
		ctx.Logv("  tiles: %d  saved: %s", types.TileCount(gfxData, opts.BPP), pngPath)
	}
	return &Result{
		Includes: []Include{{Path: binPath, Addr: ctx.Start(), Name: ctx.Seg.Name}},
		IsBinary: true,
	}, nil
}