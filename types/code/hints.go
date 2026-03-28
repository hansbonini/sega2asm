package code

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"sega2asm/types"
)

// buildHintsMap converts a slice of hints to offset → hint map.
func buildHintsMap(hints []types.Hint) map[uint32]types.Hint {
	m := make(map[uint32]types.Hint, len(hints))
	for _, h := range hints {
		m[h.Offset] = h
	}
	return m
}

// emitHint writes data directive bytes based on a hint.
func emitHint(sb *strings.Builder, hint types.Hint, data []byte, offset uint32, cmap *types.CharMap, syms *types.SymbolTable, asmDir string) {
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
	case "ptr_table":
		for i := int(offset); i < end-3; i += 4 {
			addr := uint32(data[i])<<24 | uint32(data[i+1])<<16 | uint32(data[i+2])<<8 | uint32(data[i+3])
			label := syms.Label(addr)
			if label == "" {
				label = fmt.Sprintf("$%06X", addr)
			}
			sb.WriteString(fmt.Sprintf("\tdc.l\t%s\n", label))
		}
	case "vdp_regs":
		for i := int(offset); i < end-1; i += 2 {
			w := uint16(data[i])<<8 | uint16(data[i+1])
			comment := vdpWordComment(w)
			if comment == "" {
				sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\n", w))
			} else {
				sb.WriteString(fmt.Sprintf("\tdc.w\t$%04X\t; %s\n", w, comment))
			}
		}
	case "vdp_cmds":
		for i := int(offset); i < end-3; i += 4 {
			l := uint32(data[i])<<24 | uint32(data[i+1])<<16 | uint32(data[i+2])<<8 | uint32(data[i+3])
			comment := vdpLongComment(l)
			if comment == "" {
				sb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\n", l))
			} else {
				sb.WriteString(fmt.Sprintf("\tdc.l\t$%08X\t; %s\n", l, comment))
			}
		}
	case "ptr_table_rel":
		baseAddr := uint32(hint.Base)
		baseLabel := syms.Label(baseAddr)
		if baseLabel == "" {
			if hint.Label != "" {
				baseLabel = hint.Label
			} else {
				baseLabel = fmt.Sprintf("$%06X", baseAddr)
			}
		}
		for i := int(offset); i < end-1; i += 2 {
			delta := int16(uint16(data[i])<<8 | uint16(data[i+1]))
			target := uint32(int32(baseAddr) + int32(delta))
			targetLabel := syms.Label(target)
			if targetLabel == "" {
				targetLabel = fmt.Sprintf("loc_%06X", target)
			}
			sb.WriteString(fmt.Sprintf("\tdc.w\t%s-%s\n", targetLabel, baseLabel))
		}
	case "bin":
		fileName := hint.File
		if fileName == "" {
			if hint.Label != "" {
				fileName = hint.Label + ".bin"
			} else {
				fileName = fmt.Sprintf("blob_%06X.bin", offset)
			}
		}
		if asmDir != "" {
			binPath := filepath.Join(asmDir, fileName)
			if err := os.MkdirAll(filepath.Dir(binPath), 0755); err == nil {
				_ = os.WriteFile(binPath, data[offset:end], 0644)
			}
		}
		sb.WriteString(fmt.Sprintf("\tincbin\t\"%s\"\n", fileName))
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
