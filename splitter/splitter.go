// Package splitter orchestrates the ROM splitting process.
package splitter

import (
	"crypto/sha1"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sega2asm/disasm/m68k"
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
	labels     *types.Labels
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

	// ── Order segments and make sure they cover the whole ROM ─────────────
	s.normaliseSegments(r)

	// ── Global label pass ─────────────────────────────────────────────────
	labels := segments.CollectLabels(cfg, r, syms, s.warn)
	s.labels = labels
	s.log("[SYM] Global labels: %d", len(labels.ByAddr))

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
		Labels:   labels,
		Config:   cfg,
		BaseDir:  base,
		Assets:   map[string][]byte{},
		Deferred: &[]func(){},
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

		// Z80 lookahead: absorb consecutive bin segments as embedded data
		// (the dc.b form stays in the 68000 address space and needs none).
		if strings.EqualFold(seg.Type, "z80") && !strings.EqualFold(seg.Format, "bytes") {
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

	for _, fn := range *ctx.Deferred {
		fn()
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

		macrosPath, err := s.writeMacros(asmDir)
		if err != nil {
			return fmt.Errorf("writing macros.asm: %w", err)
		}
		includes = append([]segments.Include{{Path: macrosPath}}, includes...)

		if structsPath, err := s.writeStructs(asmDir); err != nil {
			return fmt.Errorf("writing structs.asm: %w", err)
		} else if structsPath != "" {
			includes = append([]segments.Include{{Path: structsPath}}, includes...)
		}

		varsPath, err := s.writeVariables(labels, r, asmDir)
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

; ── YM2612 (68000 access while holding the Z80 bus) ─────────────────────────
YM2612_A0		equ	$00A04000	; Part I register address
YM2612_D0		equ	$00A04001	; Part I register data
YM2612_A1		equ	$00A04002	; Part II register address
YM2612_D1		equ	$00A04003	; Part II register data

; ── I/O ports ────────────────────────────────────────────────────────────────
IO_PCBVER		equ	$00A10001	; Version register (hardware version / region)
IO_DATA_1		equ	$00A10003	; Controller port 1 data
IO_DATA_2		equ	$00A10005	; Controller port 2 data
IO_DATA_EXP		equ	$00A10007	; Expansion port data
IO_CTRL_12_W	equ	$00A10008	; Controller 1+2 control (word/long access)
IO_CTRL_EXP_W	equ	$00A1000C	; Expansion control (word access)
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

func (s *Splitter) writeVariables(labels *types.Labels, r *types.ROM, asmDir string) (string, error) {
	var addrs []uint32
	for a := range labels.ByAddr {
		if a >= uint32(r.Size) && m68k.HWPortName(a) != labels.ByAddr[a] {
			addrs = append(addrs, a)
		}
	}
	if len(addrs) == 0 {
		return "", nil
	}
	sort.Slice(addrs, func(i, j int) bool { return addrs[i] < addrs[j] })

	outPath := filepath.Join(asmDir, "include", "variables.asm")
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}

	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString("; RAM variables and other addresses outside the ROM\n\n")
	for _, a := range addrs {
		line := fmt.Sprintf("%-32s\tequ\t$%08X", labels.ByAddr[a], a)
		if c := labels.Comments[a]; c != "" {
			line += "\t; " + strings.ReplaceAll(c, "\\n", " ")
		}
		sb.WriteString(line + "\n")
	}
	return outPath, os.WriteFile(outPath, []byte(sb.String()), 0644)
}

func (s *Splitter) writeMacros(asmDir string) (string, error) {
	outPath := filepath.Join(asmDir, "include", "macros.asm")
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}
	content := "; Auto-generated by sega2asm\n; Assembler support macros\n\n" + m68k.Macros
	return outPath, os.WriteFile(outPath, []byte(content), 0644)
}

// writeStructs emits the structure field offsets declared in the config.
func (s *Splitter) writeStructs(asmDir string) (string, error) {
	if len(s.cfg.Structs) == 0 {
		return "", nil
	}
	var names []string
	for n := range s.cfg.Structs {
		names = append(names, n)
	}
	sort.Strings(names)
	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n; Structure field offsets\n")
	for _, n := range names {
		sb.WriteString(fmt.Sprintf("\n; ── %s ──\n", n))
		fields := append([]types.StructField(nil), s.cfg.Structs[n]...)
		sort.SliceStable(fields, func(i, j int) bool { return int16(fields[i].Offset) < int16(fields[j].Offset) })
		for _, f := range fields {
			line := fmt.Sprintf("%-24s\tequ\t%s", f.Name, signedHexStr(int16(uint16(f.Offset))))
			if f.Comment != "" {
				line += "\t; " + f.Comment
			}
			sb.WriteString(line + "\n")
		}
	}
	outPath := filepath.Join(asmDir, "include", "structs.asm")
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}
	return outPath, os.WriteFile(outPath, []byte(sb.String()), 0644)
}

func signedHexStr(v int16) string {
	if v < 0 {
		return fmt.Sprintf("-$%X", -int32(v))
	}
	return fmt.Sprintf("$%X", v)
}

// normaliseSegments sorts segments by address, reports overlaps and fills
// uncovered ROM ranges with bin segments so a rebuild is always complete.
func (s *Splitter) normaliseSegments(r *types.ROM) {
	cfg := s.cfg
	segs := cfg.Segments
	sort.SliceStable(segs, func(i, j int) bool { return segs[i].Start < segs[j].Start })
	fill := cfg.Options.FillGaps == nil || *cfg.Options.FillGaps
	var out []types.Segment
	cur := uint32(0)
	romEnd := uint32(r.Size)
	gap := func(a, b uint32) {
		if !fill || b <= a {
			return
		}
		s.warn("ROM range $%06X–$%06X is not covered by any segment; adding bin segment", a, b)
		out = append(out, types.Segment{
			Name: fmt.Sprintf("unk_%06X", a), Type: "bin", Start: types.HexInt(a), End: types.HexInt(b),
			SubDir: "unknown", Compression: "none",
		})
	}
	for _, seg := range segs {
		st, en := uint32(seg.Start), uint32(seg.End)
		if en > romEnd {
			en = romEnd
		}
		if st < cur {
			s.warn("segment %s ($%06X) overlaps the previous segment (ends $%06X)", seg.Name, st, cur)
		} else {
			gap(cur, st)
		}
		out = append(out, seg)
		if en > cur {
			cur = en
		}
	}
	gap(cur, romEnd)
	cfg.Segments = out
}

// ---------------------------------------------------------------------------
// Main ASM include file
// ---------------------------------------------------------------------------

func (s *Splitter) writeMainASM(path string, includes []segments.Include, romEnd uint32) error {
	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString(fmt.Sprintf("; Project: %s\n", s.cfg.Name))
	sb.WriteString(fmt.Sprintf("; Build from %s:  clownassembler -i %s -o %s.bin\n\n",
		s.cfg.Options.BasePath, filepath.ToSlash(filepath.Join(s.cfg.Options.AsmPath, s.cfg.Options.Basename+".asm")),
		filepath.ToSlash(filepath.Join(s.cfg.Options.BuildPath, s.cfg.Options.Basename))))
	sb.WriteString("\torg\t$00000000\n")
	sb.WriteString("RomStart:\n\n")
	base := s.cfg.Options.BasePath
	for _, inc := range includes {
		if rel, err := filepath.Rel(base, inc.Path); err == nil {
			inc.Path = filepath.ToSlash(rel)
		}
		if strings.HasSuffix(inc.Path, ".asm") {
			sb.WriteString(fmt.Sprintf("\tinclude\t'%s'\n", inc.Path))
		} else if strings.HasSuffix(inc.Path, ".bin") {
			sb.WriteString(fmt.Sprintf("\n\torg\t$%06X\n", inc.Addr))
			if def := s.labels.Def(inc.Addr); def != "" {
				sb.WriteString(def)
			} else if inc.Name != "" {
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
