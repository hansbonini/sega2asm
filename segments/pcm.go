package segments

import (
	"os"

	"sega2asm/types/audio"
)

func init() {
	Register("pcm", processPCM)
}

func processPCM(ctx *Context) (*Result, error) {
	binPath := ctx.SegPath(ctx.AssetDir, ".bin")
	wavPath := ctx.SegPath(ctx.AssetDir, ".wav")
	if ctx.DryRun {
		return &Result{Includes: []Include{{Path: binPath, Addr: ctx.Start(), Name: ctx.Seg.Name}}, IsBinary: true}, nil
	}
	if err := ctx.EnsureDir(binPath); err != nil {
		return nil, err
	}

	data := ctx.ROMData()
	if err := os.WriteFile(binPath, data, 0644); err != nil {
		return nil, err
	}

	rate := ctx.Seg.SampleRate
	if err := audio.WritePCMAsWAV(data, wavPath, rate); err != nil {
		ctx.Warn("  PCM → WAV failed: %v", err)
	} else {
		ctx.Logv("  PCM → WAV: %s (%d samples @ %d Hz)", wavPath, len(data), audio.NormalizeSampleRate(rate))
	}
	return &Result{
		Includes: []Include{{Path: binPath, Addr: ctx.Start(), Name: ctx.Seg.Name}},
		IsBinary: true,
	}, nil
}
