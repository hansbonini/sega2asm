// Package splitter orchestrates the ROM splitting process.
package splitter

import (
	"crypto/sha1"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/segments"
	"sega2asm/types"
)

// Options controls splitter runtime behaviour.
type Options struct {
	Verbose bool
	DryRun  bool
}

// Splitter is the main splitting engine.
type Splitter struct {
	cfg        *types.Config
	opts       Options
	labelHits  int
	labelTotal int
}

// New creates a Splitter.
func New(cfg *types.Config, opts Options) *Splitter {
	return &Splitter{cfg: cfg, opts: opts}
}

// Run performs the full split.
func (s *Splitter) Run() error {
	cfg := s.cfg

	// ── Load ROM ──────────────────────────────────────────────────────────
	romPath := cfg.Options.TargetPath
	if romPath == "" {
		return fmt.Errorf("options.target_path not set in config")
	}
	s.log("[ROM] Loading %s", romPath)
	r, err := types.LoadROM(romPath)
	if err != nil {
		return err
	}
	s.log("[ROM] Size: %d bytes (%.1f KB)", r.Size, float64(r.Size)/1024)
	s.log("[ROM] Header:\n%s", r.PrintHeader())

	// ── SHA1 check ───────────────────────────────────────────────────────
	if cfg.SHA1 != "" {
		sum := fmt.Sprintf("%X", sha1.Sum(r.Data))
		if !strings.EqualFold(sum, cfg.SHA1) {
			return fmt.Errorf("SHA1 mismatch: got %s, expected %s", sum, cfg.SHA1)
		}
		s.log("[ROM] SHA1 OK: %s", sum)
	}

	// ── Load symbols ─────────────────────────────────────────────────────
	syms, err := types.LoadSymbols(cfg.Options.SymbolsPath)
	if err != nil {
		return err
	}
	s.log("[SYM] Loaded %d symbols from %s", len(syms.Ordered), cfg.Options.SymbolsPath)

	// ── Inject segment names as symbols (lower priority than symbols file) ─
	for _, seg := range cfg.Segments {
		if seg.Name != "" {
			syms.Add(uint32(seg.Start), seg.Name)
		}
	}

	// ── Load charmap ─────────────────────────────────────────────────────
	cmap, err := types.LoadCharmap(cfg.Options.CharmapPath)
	if err != nil {
		return err
	}
	if !cmap.Empty() {
		s.log("[TBL] Charmap loaded from %s", cfg.Options.CharmapPath)
	}

	// ── Create output directories ─────────────────────────────────────────
	base := cfg.Options.BasePath
	asmDir := filepath.Join(base, cfg.Options.AsmPath)
	assetDir := filepath.Join(base, cfg.Options.AssetPath)
	buildDir := filepath.Join(base, cfg.Options.BuildPath)

	if !s.opts.DryRun {
		for _, d := range []string{asmDir, assetDir, buildDir} {
			if err := os.MkdirAll(d, 0755); err != nil {
				return fmt.Errorf("creating dir %s: %w", d, err)
			}
		}
	}

	// ── Build segment processing context ──────────────────────────────────
	ctx := &segments.Context{
		ROM:      r,
		Syms:     syms,
		Charmap:  cmap,
		AsmDir:   asmDir,
		AssetDir: assetDir,
		DryRun:   s.opts.DryRun,
		Verbose:  s.opts.Verbose,
		Log:      s.log,
		Logv:     s.logv,
		Warn:     s.warn,
	}

	// ── Build global include list ─────────────────────────────────────────
	var includes []segments.Include
	var splitHints []string

	// ── Process segments ─────────────────────────────────────────────────
	segs := cfg.Segments
	for i := 0; i < len(segs); i++ {
		seg := segs[i]
		s.log("[SEG %d/%d] %s (%s) $%06X–$%06X",
			i+1, len(segs), seg.Name, seg.Type,
			uint32(seg.Start), uint32(seg.End))

		if uint32(seg.End) <= uint32(seg.Start) {
			s.warn("  skipping: end <= start")
			continue
		}
		if int(seg.Start) >= r.Size {
			s.warn("  skipping: $%06X is beyond ROM end $%06X (%.0f KB)",
				uint32(seg.Start), r.Size, float64(r.Size)/1024)
			continue
		}

		// Set the current segment on the context.
		ctx.Seg = seg
		ctx.ExtraBins = nil

		// Z80 lookahead: absorb consecutive bin segments as embedded data.
		if strings.EqualFold(seg.Type, "z80") {
			var extraBins []segments.Include
			for j := i + 1; j < len(segs); j++ {
				next := segs[j]
				if !strings.EqualFold(next.Type, "bin") || next.SubDir != seg.SubDir {
					break
				}
				// Write the bin segment.
				ctx.Seg = next
				binResult, binErr := segments.Lookup("bin")(ctx)
				if binErr == nil && len(binResult.Includes) > 0 {
					extraBins = append(extraBins, binResult.Includes[0])
				}
				i++
			}
			ctx.Seg = seg
			ctx.ExtraBins = extraBins
		}

		// Look up the processor for this segment type.
		typeName := strings.ToLower(seg.Type)
		fn := segments.Lookup(typeName)
		if fn == nil {
			s.warn("  unknown segment type %q – writing as bin", seg.Type)
			fn = segments.Lookup("bin")
		}

		result, err := fn(ctx)
		if err != nil {
			s.warn("  error: %v", err)
			continue
		}

		includes = append(includes, result.Includes...)
		splitHints = append(splitHints, result.Hints...)
		s.labelHits += result.LabelHits
	}

	s.labelTotal = len(syms.Ordered)

	// ── Write ports.asm and prepend to includes ───────────────────────────
	if cfg.Options.HeaderOutput && !s.opts.DryRun {
		portsPath, err := s.writePorts(asmDir)
		if err != nil {
			return fmt.Errorf("writing ports.asm: %w", err)
		}
		includes = append([]segments.Include{{Path: portsPath}}, includes...)
		s.log("[OUT] Hardware registers: %s", portsPath)

		varsPath, err := s.writeVariables(syms, asmDir)
		if err != nil {
			return fmt.Errorf("writing variables.asm: %w", err)
		}
		if varsPath != "" {
			includes = append([]segments.Include{{Path: varsPath}}, includes...)
			s.log("[OUT] RAM variables: %s", varsPath)
		}
	}

	// ── Write main assembly include file ──────────────────────────────────
	if cfg.Options.HeaderOutput && !s.opts.DryRun {
		mainFile := filepath.Join(asmDir, cfg.Options.Basename+".asm")
		if err := s.writeMainASM(mainFile, includes, r.Header.ROMEnd); err != nil {
			return err
		}
		s.log("[OUT] Main ASM: %s", mainFile)
	}

	// ── Unified symbol report ─────────────────────────────────────────────
	s.log("")
	s.log("[SYM] Labels matched: %d / %d", s.labelHits, s.labelTotal)

	// ── Print all split suggestions grouped at the end ────────────────────
	if !s.cfg.Options.NoSuggestions && len(splitHints) > 0 {
		s.log("")
		s.log("[HINT] Split suggestions:")
		for _, line := range splitHints {
			s.log("%s", line)
		}
	}

	return nil
}

// ---------------------------------------------------------------------------
// Hardware registers include file
// ---------------------------------------------------------------------------

func (s *Splitter) writePorts(asmDir string) (string, error) {
	incDir := filepath.Join(asmDir, "include")
	if err := os.MkdirAll(incDir, 0755); err != nil {
		return "", err
	}
	outPath := filepath.Join(incDir, "ports.asm")

	const content = `; Auto-generated by sega2asm
; Sega Mega Drive / Genesis hardware registers

; ── VDP ──────────────────────────────────────────────────────────────────────
VDP_DATA		equ	$00C00000	; VDP data port (write tile/sprite data)
VDP_DATA_W		equ	$00C00000	; VDP data port (word alias)
VDP_CTRL		equ	$00C00004	; VDP control/status port
VDP_HVCOUNTER	equ	$00C00008	; H/V counter (read only)
VDP_DEBUG		equ	$00C0001C	; VDP debug register

; ── PSG ──────────────────────────────────────────────────────────────────────
PSG_DATA		equ	$00C00011	; SN76489 PSG data port (write only)

; ── Z80 ──────────────────────────────────────────────────────────────────────
Z80_RAM			equ	$00A00000	; Z80 RAM base ($A00000–$A01FFF)
Z80_BUSREQ		equ	$00A11100	; Z80 bus request (write $0100 to request, $0000 to release)
Z80_RESET		equ	$00A11200	; Z80 reset (write $0000 to assert, $0100 to deassert)

; ── I/O ports ────────────────────────────────────────────────────────────────
IO_PCBVER		equ	$00A10001	; Version register (hardware version / region)
IO_DATA_1		equ	$00A10003	; Controller port 1 data
IO_DATA_2		equ	$00A10005	; Controller port 2 data
IO_DATA_EXP		equ	$00A10007	; Expansion port data
IO_CTRL_1		equ	$00A10009	; Controller port 1 control (direction)
IO_CTRL_2		equ	$00A1000B	; Controller port 2 control (direction)
IO_CTRL_EXP		equ	$00A1000D	; Expansion port control (direction)
IO_TXDATA_1		equ	$00A1000F	; Controller port 1 TX data (serial)
IO_RXDATA_1		equ	$00A10011	; Controller port 1 RX data (serial)
IO_SCTRL_1		equ	$00A10013	; Controller port 1 serial control
IO_TXDATA_2		equ	$00A10015	; Controller port 2 TX data (serial)
IO_RXDATA_2		equ	$00A10017	; Controller port 2 RX data (serial)
IO_SCTRL_2		equ	$00A10019	; Controller port 2 serial control
IO_TXDATA_EXP	equ	$00A1001B	; Expansion port TX data (serial)
IO_RXDATA_EXP	equ	$00A1001D	; Expansion port RX data (serial)
IO_SCTRL_EXP	equ	$00A1001F	; Expansion port serial control

; ── Memory control ───────────────────────────────────────────────────────────
MEM_MODE		equ	$00A11000	; Memory mode register
TIME_REG		equ	$00A13000	; /TIME register (cartridge banking)
TMSS_REG		equ	$00A14000	; TMSS register (write 'SEGA' to unlock VDP)
TMSS_VDP		equ	$00A14100	; TMSS VDP allow register

; ── System RAM ───────────────────────────────────────────────────────────────
RAM_START		equ	$00FF0000	; Work RAM start
RAM_END			equ	$00FFFFFF	; Work RAM end
`
	return outPath, os.WriteFile(outPath, []byte(content), 0644)
}

// ---------------------------------------------------------------------------
// RAM variables file
// ---------------------------------------------------------------------------

func (s *Splitter) writeVariables(syms *types.SymbolTable, asmDir string) (string, error) {
	var ramSyms []types.Symbol
	for _, sym := range syms.Ordered {
		addr := sym.Addr
		if addr >= 0x00FF0000 && addr <= 0x00FFFFFF {
			ramSyms = append(ramSyms, sym)
		} else if addr >= 0xFFFF8000 {
			ramSyms = append(ramSyms, sym)
		}
	}
	if len(ramSyms) == 0 {
		return "", nil
	}

	outPath := filepath.Join(asmDir, "include", "variables.asm")
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}

	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString("; Game RAM variables\n\n")
	for _, sym := range ramSyms {
		sb.WriteString(fmt.Sprintf("%-24s\tequ\t$%08X\n", sym.Name, sym.Addr))
	}
	return outPath, os.WriteFile(outPath, []byte(sb.String()), 0644)
}

// ---------------------------------------------------------------------------
// Main ASM include file
// ---------------------------------------------------------------------------

func (s *Splitter) writeMainASM(path string, includes []segments.Include, romEnd uint32) error {
	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString(fmt.Sprintf("; Project: %s\n\n", s.cfg.Name))
	sb.WriteString("\torg\t$00000000\n")
	sb.WriteString("RomStart:\n\n")
	for _, inc := range includes {
		if strings.HasSuffix(inc.Path, ".asm") || strings.HasSuffix(inc.Path, ".txt") {
			sb.WriteString(fmt.Sprintf("\tinclude\t'%s'\n", inc.Path))
		} else if strings.HasSuffix(inc.Path, ".bin") {
			sb.WriteString(fmt.Sprintf("\n\torg\t$%06X\n", inc.Addr))
			if inc.Name != "" {
				sb.WriteString(inc.Name + ":\n")
			}
			sb.WriteString(fmt.Sprintf("\tincbin\t'%s'\n", inc.Path))
		}
	}
	sb.WriteString(fmt.Sprintf("\n\torg\t$%08X\n", romEnd))
	sb.WriteString("RomEnd:\n")
	return os.WriteFile(path, []byte(sb.String()), 0644)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func (s *Splitter) log(format string, args ...any) {
	fmt.Printf(format+"\n", args...)
}

func (s *Splitter) logv(format string, args ...any) {
	if s.opts.Verbose {
		fmt.Printf(format+"\n", args...)
	}
}

func (s *Splitter) warn(format string, args ...any) {
	fmt.Printf("[WARN] "+format+"\n", args...)
}
