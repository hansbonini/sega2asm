package splitter

import (
	"bytes"
	"crypto/sha1"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"sega2asm/types"
)

// Verify assembles the generated project with clownassembler (run from the
// project base directory, which all include/incbin paths are relative to)
// and compares the output with the original ROM byte for byte.
func Verify(cfg *types.Config, assembler string) error {
	base := cfg.Options.BasePath
	mainAsm := filepath.ToSlash(filepath.Join(cfg.Options.AsmPath, cfg.Options.Basename+".asm"))
	outBin := filepath.ToSlash(filepath.Join(cfg.Options.BuildPath, cfg.Options.Basename+".bin"))
	if err := os.MkdirAll(filepath.Join(base, cfg.Options.BuildPath), 0755); err != nil {
		return err
	}
	fmt.Printf("[BUILD] (cd %s && %s -i %s -o %s)\n", base, assembler, mainAsm, outBin)
	cmd := exec.Command(assembler, "-i", mainAsm, "-o", outBin, "-p", "-w")
	cmd.Dir = base
	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		os.Stdout.Write(out)
	}
	if err != nil {
		return fmt.Errorf("assembler failed: %w", err)
	}

	rom, err := types.LoadROM(cfg.Options.TargetPath)
	if err != nil {
		return err
	}
	built, err := os.ReadFile(filepath.Join(base, outBin))
	if err != nil {
		return err
	}
	want := fmt.Sprintf("%X", sha1.Sum(rom.Data))
	got := fmt.Sprintf("%X", sha1.Sum(built))
	fmt.Printf("[VERIFY] original SHA-1 %s (%d bytes)\n", want, len(rom.Data))
	fmt.Printf("[VERIFY] rebuilt  SHA-1 %s (%d bytes)\n", got, len(built))
	if bytes.Equal(rom.Data, built) {
		fmt.Println("[VERIFY] OK: rebuilt ROM is bit-identical")
		return nil
	}

	// Report the first differing ranges with the segment they belong to.
	n := len(rom.Data)
	if len(built) < n {
		n = len(built)
	}
	shown := 0
	for i := 0; i < n && shown < 20; i++ {
		if rom.Data[i] == built[i] {
			continue
		}
		j := i
		for j < n && rom.Data[j] != built[j] {
			j++
		}
		fmt.Printf("[VERIFY] mismatch $%06X–$%06X in %s\n", i, j, segmentAt(cfg, uint32(i)))
		shown++
		i = j
	}
	if len(built) != len(rom.Data) {
		fmt.Printf("[VERIFY] size differs: rebuilt %d, original %d\n", len(built), len(rom.Data))
	}
	return fmt.Errorf("rebuilt ROM differs from the original")
}

func segmentAt(cfg *types.Config, a uint32) string {
	for _, s := range cfg.Segments {
		if a >= uint32(s.Start) && a < uint32(s.End) {
			return fmt.Sprintf("%s (%s)", s.Name, s.Type)
		}
	}
	return "<no segment>"
}
