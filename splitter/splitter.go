// Package splitter orchestrates the ROM splitting process.
package splitter

import (
	"crypto/sha1"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/audio"
	"sega2asm/charmap"
	"sega2asm/compress"
	"sega2asm/config"
	"sega2asm/disasm/m68k"
	"sega2asm/disasm/z80"
	"sega2asm/gfx"
	"sega2asm/rom"
	"sega2asm/symbols"
)

// Options controls splitter runtime behaviour.
type Options struct {
	Verbose bool
	DryRun  bool
}

// Splitter is the main splitting engine.
type Splitter struct {
	cfg  *config.Config
	opts Options
}

// New creates a Splitter.
func New(cfg *config.Config, opts Options) *Splitter {
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
	r, err := rom.Load(romPath)
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
	syms, err := symbols.Load(cfg.Options.SymbolsPath)
	if err != nil {
		return err
	}
	s.log("[SYM] Loaded %d symbols from %s", len(syms.Ordered), cfg.Options.SymbolsPath)

	// ── Load charmap ─────────────────────────────────────────────────────
	cmap, err := charmap.Load(cfg.Options.CharmapPath)
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

	// ── Build global include list ─────────────────────────────────────────
	var includes []incEntry

	// ── Process segments ─────────────────────────────────────────────────
	for i, seg := range cfg.Segments {
		s.log("[SEG %d/%d] %s (%s) $%06X–$%06X",
			i+1, len(cfg.Segments), seg.Name, seg.Type,
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

		var outPath string
		var err error
		isBin := false

		switch strings.ToLower(seg.Type) {
		case "header":
			var paths []string
			paths, err = s.writeHeader(r, seg, asmDir)
			if err != nil {
				s.warn("  error: %v", err)
				continue
			}
			for _, p := range paths {
				if p != "" {
					includes = append(includes, incEntry{path: p})
				}
			}
			continue
		case "m68k":
			outPath, err = s.writeM68K(r, seg, asmDir, syms, cmap)
		case "z80":
			outPath, err = s.writeZ80(r, seg, asmDir, syms)
		case "gfx":
			outPath, err = s.writeGFX(r, seg, assetDir, false)
			isBin = true
		case "gfxcomp":
			outPath, err = s.writeGFX(r, seg, assetDir, true)
			isBin = true
		case "pcm":
			outPath, err = s.writePCM(r, seg, assetDir)
			isBin = true
		case "psg":
			outPath, err = s.writePSG(r, seg, assetDir)
			isBin = true
		case "text":
			outPath, err = s.writeText(r, seg, assetDir, cmap)
		case "bin":
			outPath, err = s.writeBin(r, seg, assetDir)
			isBin = true
		default:
			s.warn("  unknown segment type %q – writing as bin", seg.Type)
			outPath, err = s.writeBin(r, seg, assetDir)
			isBin = true
		}

		if err != nil {
			s.warn("  error: %v", err)
			continue
		}

		if outPath != "" {
			addr := uint32(0)
			if isBin {
				addr = uint32(seg.Start)
			}
			includes = append(includes, incEntry{path: outPath, addr: addr})
		}
	}

	// ── Write main assembly include file ──────────────────────────────────
	if cfg.Options.HeaderOutput && !s.opts.DryRun {
		mainFile := filepath.Join(asmDir, cfg.Options.Basename+".asm")
		if err := s.writeMainASM(mainFile, includes); err != nil {
			return err
		}
		s.log("[OUT] Main ASM: %s", mainFile)
	}

	return nil
}

// ---------------------------------------------------------------------------
// Segment writers
// ---------------------------------------------------------------------------

func (s *Splitter) writeHeader(r *rom.ROM, seg config.Segment, dir string) ([]string, error) {
	segDir := filepath.Join(dir, func() string {
		if seg.SubDir != "" {
			return seg.SubDir
		}
		return strings.ToLower(seg.Type)
	}())
	interruptsPath := filepath.Join(segDir, "interrupts.asm")
	headerPath := s.segPath(seg, dir, ".asm")

	if s.opts.DryRun {
		return []string{interruptsPath, headerPath}, nil
	}
	if err := os.MkdirAll(segDir, 0755); err != nil {
		return nil, err
	}

	// ── interrupts.asm ($000000–$0000FF) ──────────────────────────────────
	var iv strings.Builder
	iv.WriteString("; Auto-generated by sega2asm\n")
	iv.WriteString("; Interrupt Vector Table\n\n")
	iv.WriteString("\torg\t$000000\n\n")

	vectorLabels := []string{
		"InitialSSP", "InitialPC", "BusError", "AddressError",
		"IllegalInstr", "ZeroDivide", "CHKExcept", "TRAPVExcept",
		"PrivilegeViol", "TraceExcept", "Line1010Emul", "Line1111Emul",
		"Reserved0C", "Reserved0D", "Reserved0E", "UninitialisedISR",
		"Reserved10", "Reserved11", "Reserved12", "Reserved13",
		"Reserved14", "Reserved15", "Reserved16", "Reserved17",
		"SpuriousIRQ", "IRQ1", "EXT_IRQ", "IRQ3",
		"HBLANK_IRQ", "IRQ5", "VBLANK_IRQ", "IRQ7",
	}
	for i, label := range vectorLabels {
		v := r.Read32(uint32(i * 4))
		iv.WriteString(fmt.Sprintf("%-24s\tdc.l\t$%08X\n", label+":", v))
	}
	for i := 32; i < 64; i++ {
		v := r.Read32(uint32(i * 4))
		iv.WriteString(fmt.Sprintf("TRAP_%02d:\t\t\tdc.l\t$%08X\n", i-32, v))
	}
	if err := os.WriteFile(interruptsPath, []byte(iv.String()), 0644); err != nil {
		return nil, err
	}

	// ── header.asm ($000100–$0001FF) ──────────────────────────────────────
	var hb strings.Builder
	hb.WriteString("; Auto-generated by sega2asm\n")
	hb.WriteString("; Mega Drive ROM Header\n\n")
	hb.WriteString("\torg\t$000100\n\n")

	h := r.Header
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-16s'\n", h.SystemName))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-16s'\n", h.Copyright))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-48s'\n", h.DomesticName))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-48s'\n", h.OverseasName))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%s'\n", h.SerialType))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-12s'\n", h.Serial))
	hb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\t; Checksum\n", h.Checksum))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-16s'\n", h.DeviceSupport))
	hb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; ROM start\n", h.ROMStart))
	hb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; ROM end\n", h.ROMEnd))
	hb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; RAM start\n", h.RAMStart))
	hb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; RAM end\n", h.RAMEnd))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-12s'\n", h.SRAMInfo))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-52s'\n", h.Notes))
	hb.WriteString(fmt.Sprintf("\tdc.b\t'%-16s'\t; Region\n", h.RegionCodes))

	if err := os.WriteFile(headerPath, []byte(hb.String()), 0644); err != nil {
		return nil, err
	}

	return []string{interruptsPath, headerPath}, nil
}

func (s *Splitter) writeM68K(r *rom.ROM, seg config.Segment, dir string, syms *symbols.Table, cmap *charmap.Map) (string, error) {
	outPath := s.segPath(seg, dir, ".asm")
	if s.opts.DryRun {
		return outPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}

	start := uint32(seg.Start)
	end := uint32(seg.End)
	if int(end) > r.Size {
		end = uint32(r.Size)
	}
	data := r.Slice(start, end)

	// Build hints map
	hints := buildHintsMap(seg.Hints)

	// Pass start as baseAddr: PC = start+pos, matching ROM symbol addresses.
	// Branch/jump targets computed with correct ROM addresses are then
	// resolved to label names from syms.ByAddr inside the disassembler.
	results := m68k.DisassembleBlock(data, start, 0, uint32(len(data)), syms.ByAddr)

	vdp := newVDPAnnotator(syms.Label(0xC00004))

	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString(fmt.Sprintf("; Segment: %s  $%06X–$%06X\n\n", seg.Name, start, end))
	sb.WriteString(fmt.Sprintf("\torg\t$%06X\n\n", start))

	labelHits := 0
	for _, res := range results {
		addr := res.Addr

		// Emit a named label when this address has a symbol.
		// The blank line before it visually separates subroutines/data blocks.
		hasLabel := syms.Has(addr)
		if hasLabel {
			labelHits++
			s.logv("  [label] %s = $%06X", syms.Label(addr), addr)
			sb.WriteByte('\n')
			sb.WriteString(syms.Label(addr) + ":")
			sb.WriteString(fmt.Sprintf("\t\t\t\t; $%06X\n", addr))
		} else if addr == r.InitialPC {
			// Automatically label the ROM entry point when no symbol is defined.
			sb.WriteByte('\n')
			sb.WriteString("EntryPoint:")
			sb.WriteString(fmt.Sprintf("\t\t\t\t; $%06X\n", addr))
		}

		// Check hints: override with explicit data directives.
		if hint, ok := hints[addr-start]; ok {
			s.emitHint(&sb, hint, data, addr-start, cmap)
			continue
		}

		// No named symbol: emit address comment for orientation.
		if !hasLabel {
			sb.WriteString(fmt.Sprintf("; $%06X\n", addr))
		}
		sb.WriteString(vdp.annotate(res.Text))
		sb.WriteByte('\n')
	}
	s.log("[SYM]  labels matched: %d / %d symbols", labelHits, len(syms.Ordered))
	s.suggestM68KSplits(results, seg, syms)

	return outPath, os.WriteFile(outPath, []byte(sb.String()), 0644)
}

func (s *Splitter) writeZ80(r *rom.ROM, seg config.Segment, dir string, syms *symbols.Table) (string, error) {
	outPath := s.segPath(seg, dir, ".asm")
	if s.opts.DryRun {
		return outPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}

	start := uint32(seg.Start)
	end := uint32(seg.End)
	if int(end) > r.Size {
		end = uint32(r.Size)
	}
	data := r.Slice(start, end)

	// Z80 uses its own address space.  z80_org defaults to $0000 (most drivers)
	// but can be set in the YAML for overlays that load at a non-zero Z80 address.
	z80Org := uint32(seg.Z80Org)
	results := z80.DisassembleBlock(data, 0, z80Org, uint32(len(data)), syms.ByAddr)

	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString(fmt.Sprintf("; Z80 Segment: %s  ROM:$%06X–$%06X\n\n", seg.Name, start, end))
	sb.WriteString(fmt.Sprintf("\torg\t$%04X\n\n", z80Org))

	labelHits := 0
	for _, res := range results {
		addr := res.Addr
		hasLabel := syms.Has(addr)
		if hasLabel {
			labelHits++
			s.logv("  [label] %s = $%04X", syms.Label(addr), addr)
			sb.WriteByte('\n')
			sb.WriteString(syms.Label(addr) + ":")
			sb.WriteString(fmt.Sprintf("\t\t\t\t; $%04X\n", addr))
		} else {
			sb.WriteString(fmt.Sprintf("; $%04X\n", addr))
		}
		sb.WriteString(res.Text)
		sb.WriteByte('\n')
	}
	s.log("[SYM]  labels matched: %d / %d symbols", labelHits, len(syms.Ordered))

	return outPath, os.WriteFile(outPath, []byte(sb.String()), 0644)
}

func (s *Splitter) writeGFX(r *rom.ROM, seg config.Segment, dir string, compressed bool) (string, error) {
	binPath := s.segPath(seg, dir, ".bin")
	pngPath := s.segPath(seg, dir, ".png")
	if s.opts.DryRun {
		return binPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(binPath), 0755); err != nil {
		return "", err
	}

	rawData := r.Slice(uint32(seg.Start), uint32(seg.End))

	// Always save original (possibly compressed) bytes for incbin.
	if err := os.WriteFile(binPath, rawData, 0644); err != nil {
		return "", err
	}

	// Decompress and save decompressed binary + render PNG for reference only.
	gfxData := rawData
	if compressed {
		dec, err := compress.Decompress(seg.Compression, rawData)
		if err != nil {
			s.warn("  decompression failed (%s): %v – PNG skipped", seg.Compression, err)
		} else {
			gfxData = dec
			decPath := s.segPath(seg, dir, ".decompressed.bin")
			if err := os.WriteFile(decPath, gfxData, 0644); err != nil {
				s.warn("  writing decompressed bin failed: %v", err)
			}
		}
	}
	opts := gfx.Options{TilesPerRow: 16, Scale: 2}
	if err := gfx.DumpTiles(gfxData, pngPath, opts); err != nil {
		s.warn("  PNG render failed: %v", err)
	} else {
		s.logv("  tiles: %d  saved: %s", gfx.TileCount(gfxData), pngPath)
	}
	return binPath, nil
}

func (s *Splitter) writePCM(r *rom.ROM, seg config.Segment, dir string) (string, error) {
	binPath := s.segPath(seg, dir, ".bin")
	wavPath := s.segPath(seg, dir, ".wav")
	if s.opts.DryRun {
		return binPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(binPath), 0755); err != nil {
		return "", err
	}

	data := r.Slice(uint32(seg.Start), uint32(seg.End))

	// Save original raw PCM bytes for incbin.
	if err := os.WriteFile(binPath, data, 0644); err != nil {
		return "", err
	}

	// Convert to WAV for preview only.
	rate := seg.SampleRate
	if rate == 0 {
		rate = 7040
	}
	if err := audio.PCMToWAV(data, wavPath, rate); err != nil {
		s.warn("  PCM → WAV failed: %v", err)
	} else {
		s.logv("  PCM → WAV: %s (%d samples @ %d Hz)", wavPath, len(data), rate)
	}
	return binPath, nil
}

func (s *Splitter) writePSG(r *rom.ROM, seg config.Segment, dir string) (string, error) {
	binPath := s.segPath(seg, dir, ".bin")
	midPath := s.segPath(seg, dir, ".mid")
	if s.opts.DryRun {
		return binPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(binPath), 0755); err != nil {
		return "", err
	}

	data := r.Slice(uint32(seg.Start), uint32(seg.End))

	// Save original raw bytes for incbin.
	if err := os.WriteFile(binPath, data, 0644); err != nil {
		return "", err
	}

	// Convert to MIDI for preview only.
	events, err := audio.ParseVGMPSGEvents(data)
	if err != nil || len(events) == 0 {
		events = nil
		for i := 0; i+1 < len(data); i += 2 {
			events = append(events, audio.PSGEvent{
				Tick:     uint32(i / 2),
				Register: data[i] >> 5 & 0x3 * 2 + data[i]>>4&1,
				Value:    uint16(data[i+1]),
			})
		}
	}
	if err := audio.PSGToMIDI(events, midPath, 480); err != nil {
		s.warn("  PSG → MIDI failed: %v", err)
	} else {
		s.logv("  PSG → MIDI: %s (%d events)", midPath, len(events))
	}
	return binPath, nil
}

func (s *Splitter) writeText(r *rom.ROM, seg config.Segment, dir string, cmap *charmap.Map) (string, error) {
	outPath := s.segPath(seg, dir, ".txt")
	if s.opts.DryRun {
		return outPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}

	data := r.Slice(uint32(seg.Start), uint32(seg.End))
	var out string
	if !cmap.Empty() {
		out = cmap.DecodeString(data, 0x00)
	} else {
		// ASCII fallback
		out = strings.Map(func(r rune) rune {
			if r >= 0x20 && r < 0x7F {
				return r
			}
			return '.'
		}, string(data))
	}
	return outPath, os.WriteFile(outPath, []byte(out), 0644)
}

func (s *Splitter) writeBin(r *rom.ROM, seg config.Segment, dir string) (string, error) {
	outPath := s.segPath(seg, dir, ".bin")
	if s.opts.DryRun {
		return outPath, nil
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return "", err
	}
	data := r.Slice(uint32(seg.Start), uint32(seg.End))
	return outPath, os.WriteFile(outPath, data, 0644)
}

// ---------------------------------------------------------------------------
// Main ASM include file
// ---------------------------------------------------------------------------

// incEntry pairs an output file with the ROM start address it covers.
// For .asm files addr is 0 (the file already contains its own org directive).
// For .bin files addr is the segment start, emitted as "org $ADDR + incbin".
type incEntry struct {
	path string
	addr uint32
}

func (s *Splitter) writeMainASM(path string, includes []incEntry) error {
	var sb strings.Builder
	sb.WriteString("; Auto-generated by sega2asm\n")
	sb.WriteString(fmt.Sprintf("; Project: %s\n\n", s.cfg.Name))
	for _, inc := range includes {
		if strings.HasSuffix(inc.path, ".asm") {
			sb.WriteString(fmt.Sprintf("\tinclude\t'%s'\n", inc.path))
		} else if strings.HasSuffix(inc.path, ".bin") {
			sb.WriteString(fmt.Sprintf("\n\torg\t$%06X\n", inc.addr))
			sb.WriteString(fmt.Sprintf("\tincbin\t'%s'\n", inc.path))
		}
	}
	return os.WriteFile(path, []byte(sb.String()), 0644)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func (s *Splitter) segPath(seg config.Segment, baseDir, ext string) string {
	if seg.OutputPath != "" {
		return seg.OutputPath
	}
	subdir := seg.SubDir
	if subdir == "" {
		subdir = strings.ToLower(seg.Type)
	}
	name := seg.Name
	if name == "" {
		name = fmt.Sprintf("seg_%06X", uint32(seg.Start))
	}
	return filepath.Join(baseDir, subdir, name+ext)
}

// log prints always. logv prints only in verbose mode.
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

// buildHintsMap converts a slice of hints to offset → hint map.
func buildHintsMap(hints []config.Hint) map[uint32]config.Hint {
	m := make(map[uint32]config.Hint, len(hints))
	for _, h := range hints {
		m[h.Offset] = h
	}
	return m
}

// emitHint writes data directive bytes based on a hint.
func (s *Splitter) emitHint(sb *strings.Builder, hint config.Hint, data []byte, offset uint32, cmap *charmap.Map) {
	if hint.Label != "" {
		sb.WriteString(hint.Label + ":\n")
	}
	length := hint.Length
	if length <= 0 {
		length = 1
	}
	end := int(offset) + length
	if end > len(data) {
		end = len(data)
	}

	switch hint.Type {
	case "data_byte":
		for i := int(offset); i < end; i++ {
			sb.WriteString(fmt.Sprintf("\tdc.b\t$%02X\n", data[i]))
		}
	case "data_word":
		for i := int(offset); i < end-1; i += 2 {
			w := uint16(data[i])<<8 | uint16(data[i+1])
			sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\n", w))
		}
	case "data_long":
		for i := int(offset); i < end-3; i += 4 {
			l := uint32(data[i])<<24 | uint32(data[i+1])<<16 | uint32(data[i+2])<<8 | uint32(data[i+3])
			sb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\n", l))
		}
	case "text":
		if !cmap.Empty() {
			decoded := cmap.DecodeString(data[offset:end], 0x00)
			sb.WriteString(fmt.Sprintf("\tdc.b\t'%s',0\n", decoded))
		} else {
			sb.WriteString(fmt.Sprintf("\tdc.b\t'%s',0\n", sanitiseASCII(data[offset:end])))
		}
	case "skip":
		sb.WriteString(fmt.Sprintf("\teven\t; skip %d bytes\n", length))
	default:
		sb.WriteString(fmt.Sprintf("\tdc.b\t$%02X\t; unknown hint type\n", data[offset]))
	}
}

func sanitiseASCII(b []byte) string {
	s := make([]byte, len(b))
	for i, c := range b {
		if c >= 0x20 && c < 0x7F && c != '\'' {
			s[i] = c
		} else {
			s[i] = '.'
		}
	}
	return string(s)
}


