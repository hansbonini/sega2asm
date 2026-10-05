package code

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/types"
)

// BuildHintsMap converts a slice of hints to offset → hint map.
func BuildHintsMap(hints []types.Hint) map[uint32]types.Hint {
	m := make(map[uint32]types.Hint, len(hints))
	for _, h := range hints {
		m[h.Offset] = h
	}
	return m
}

// HintEnv carries what EmitHint needs besides the hint itself.
type HintEnv struct {
	ROM     []byte
	Charmap *types.CharMap
	Labels  *types.Labels
	BinDir  string              // directory for extracted "bin" hints
	Rel     func(string) string // path relative to the assembler base dir
}

// EmitHint writes the data directives for a hint located at ROM address
// addr. The output always reproduces the original bytes exactly.
func EmitHint(sb *strings.Builder, hint types.Hint, addr uint32, env HintEnv) {
	if hint.Label != "" {
		sb.WriteString(hint.Label + ":\n")
	}
	length := hint.Length
	if length <= 0 {
		length = 1
	}
	start := int(addr)
	end := start + length
	if end > len(env.ROM) {
		end = len(env.ROM)
	}
	data := env.ROM[start:end]
	lab := func(a uint32) string {
		if n, ok := env.Labels.Get(a); ok {
			return n
		}
		return fmt.Sprintf("$%08X", a)
	}

	switch hint.Type {
	case "data_byte":
		WriteData(sb, env.ROM, addr, uint32(end), 1, env.Labels, false)
	case "data_word":
		WriteData(sb, env.ROM, addr, uint32(end), 2, env.Labels, false)
	case "data_long":
		WriteData(sb, env.ROM, addr, uint32(end), 4, env.Labels, false)
	case "ptr_table":
		n := len(data) / 4
		for i := 0; i < n; i++ {
			v := be32(data[i*4:])
			sb.WriteString("\tdc.l\t" + lab(v) + "\n")
		}
		WriteDCB(sb, data[n*4:], 16, false)
	case "ptr_table_rel":
		base := uint32(hint.Base)
		baseName, ok := env.Labels.Get(base)
		if !ok {
			baseName = fmt.Sprintf("$%06X", base)
		}
		n := len(data) / 2
		for i := 0; i < n; i++ {
			delta := int16(be16(data[i*2:]))
			target := uint32(int32(base) + int32(delta))
			if tn, ok := env.Labels.Get(target); ok && strings.HasPrefix(baseName, "$") == false {
				sb.WriteString(fmt.Sprintf("\tdc.w\t%s-%s\n", tn, baseName))
			} else {
				sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\n", uint16(delta)))
			}
		}
		WriteDCB(sb, data[n*2:], 16, false)
	case "vdp_regs":
		n := len(data) / 2
		for i := 0; i < n; i++ {
			w := be16(data[i*2:])
			if c := vdpWordComment(w); c != "" {
				sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\t; %s\n", w, c))
			} else {
				sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\n", w))
			}
		}
		WriteDCB(sb, data[n*2:], 16, false)
	case "vdp_cmds":
		n := len(data) / 4
		for i := 0; i < n; i++ {
			l := be32(data[i*4:])
			if c := vdpLongComment(l); c != "" {
				sb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; %s\n", l, c))
			} else {
				sb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\n", l))
			}
		}
		WriteDCB(sb, data[n*4:], 16, false)
	case "bin":
		fileName := hint.File
		if fileName == "" {
			if hint.Label != "" {
				fileName = hint.Label + ".bin"
			} else {
				fileName = fmt.Sprintf("blob_%06X.bin", addr)
			}
		}
		binPath := filepath.Join(env.BinDir, fileName)
		if err := os.MkdirAll(filepath.Dir(binPath), 0755); err == nil {
			_ = os.WriteFile(binPath, data, 0644)
		}
		p := binPath
		if env.Rel != nil {
			p = env.Rel(binPath)
		}
		sb.WriteString(fmt.Sprintf("\tincbin\t'%s'\n", p))
	case "text":
		if !env.Charmap.Empty() {
			sb.WriteString(fmt.Sprintf("\t; \"%s\"\n", strings.ReplaceAll(env.Charmap.DecodeAll(data), "\n", "\\n")))
		}
		WriteData(sb, env.ROM, addr, uint32(end), 1, env.Labels, true)
	default: // skip (alignment padding) and unknown types keep the exact bytes
		WriteData(sb, env.ROM, addr, uint32(end), 1, env.Labels, false)
	}
}

func be16(b []byte) uint16 { return uint16(b[0])<<8 | uint16(b[1]) }
func be32(b []byte) uint32 {
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}

func writeWords(sb *strings.Builder, data []byte, perLine int) {
	n := len(data) / 2
	for i := 0; i < n; i += perLine {
		sb.WriteString("\tdc.w\t")
		for j := i; j < i+perLine && j < n; j++ {
			if j > i {
				sb.WriteByte(',')
			}
			sb.WriteString(fmt.Sprintf("$%04X", be16(data[j*2:])))
		}
		sb.WriteByte('\n')
	}
	WriteDCB(sb, data[n*2:], 16, false)
}

func writeLongs(sb *strings.Builder, data []byte, perLine int) {
	n := len(data) / 4
	for i := 0; i < n; i += perLine {
		sb.WriteString("\tdc.l\t")
		for j := i; j < i+perLine && j < n; j++ {
			if j > i {
				sb.WriteByte(',')
			}
			sb.WriteString(fmt.Sprintf("$%08X", be32(data[j*4:])))
		}
		sb.WriteByte('\n')
	}
	WriteDCB(sb, data[n*4:], 16, false)
}

// WriteDCB emits data as dc.b lines. With strings enabled, runs of three or
// more printable ASCII characters are written as quoted strings.
func WriteDCB(sb *strings.Builder, data []byte, perLine int, strs bool) {
	printable := func(c byte) bool { return c >= 0x20 && c < 0x7F && c != '\'' && c != '\\' && c != '"' }
	var items []string
	flush := func() {
		if len(items) == 0 {
			return
		}
		sb.WriteString("\tdc.b\t" + strings.Join(items, ",") + "\n")
		items = items[:0]
	}
	count := 0
	for i := 0; i < len(data); {
		if strs && printable(data[i]) {
			j := i
			for j < len(data) && printable(data[j]) {
				j++
			}
			if j-i >= 3 {
				items = append(items, "'"+string(data[i:j])+"'")
				count += j - i
				i = j
				if count >= perLine {
					flush()
					count = 0
				}
				continue
			}
		}
		items = append(items, fmt.Sprintf("$%02X", data[i]))
		count++
		i++
		if count >= perLine {
			flush()
			count = 0
		}
	}
	flush()
}

// WriteData emits rom[start:end] as dc.b / dc.w / dc.l directives, starting a
// new line and emitting "label:" at every address that has a label (except
// start itself, whose label the caller writes). unit is 1, 2 or 4; odd
// leftovers are written as bytes. With strs, printable runs become strings.
func WriteData(sb *strings.Builder, rom []byte, start, end uint32, unit int, labels *types.Labels, strs bool) {
	if unit != 2 && unit != 4 {
		unit = 1
	}
	perLine := map[int]int{1: 16, 2: 8, 4: 4}[unit]
	if strs {
		perLine = 32
	}
	a := start
	for a < end {
		// Chunk up to the next label.
		stop := end
		for b := a + 1; b < end; b++ {
			if _, ok := labels.Get(b); ok {
				stop = b
				break
			}
		}
		if a != start {
			sb.WriteString(labels.Def(a))
		}
		chunk := rom[a:stop]
		if unit > 1 && a&1 != 0 && !strs {
			// Word/long data must be even-aligned: emit the odd byte first.
			WriteDCB(sb, chunk[:1], perLine, false)
			chunk = chunk[1:]
		}
		switch {
		case strs || unit == 1:
			WriteDCB(sb, chunk, perLine, strs)
		case unit == 2:
			writeWords(sb, chunk, perLine)
		default:
			writeLongs(sb, chunk, perLine)
		}
		a = stop
	}
}
