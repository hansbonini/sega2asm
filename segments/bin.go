package segments

func init() {
	Register("bin", processBin)
}

// processBin writes the segment bytes for incbin. When a compression is set
// the decompressed data is written next to it for reference.
func processBin(ctx *Context) (*Result, error) {
	if ctx.DryRun {
		return binResult(ctx, ctx.SegPath(ctx.AssetDir, ".bin")), nil
	}
	binPath, _, err := decodeSegment(ctx, false)
	return binResult(ctx, binPath), err
}
