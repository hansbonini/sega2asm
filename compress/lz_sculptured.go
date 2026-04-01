package compress

import (
	"encoding/binary"
	"fmt"
	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{
		Name:        "lzsculptured",
		Family:      types.FamilyMixed,
		Description: "Sculptured Software multi-mode LZ+RLE (Mortal Kombat 3); 4-byte header (u16be mode + u16be param), then byte-command or bitstream decompression",
		Decompress:  DecompressLZSculptured,
	})
	types.RegisterSignature(types.CompressSig{
		Name:        "lzsculptured",
		WordAligned: true,
		Sig:         []byte{0x72, 0x00, 0x12, 0x00, 0xE7, 0x49, 0x12, 0x18, 0x52, 0x41, 0x24, 0x49, 0x94, 0xC1, 0xC0, 0x45, 0x4E, 0xF4, 0x00, 0x00},
	})
}

// DecompressLZSculptured decompresses data using the Sculptured Software multi-mode
// LZ+RLE format (Mortal Kombat 3).
//
// Header: 4 bytes — u16be mode + u16be param.
//
// Mode 0: byte-command stream; 0x00 terminates.
//
//	0x01..0x1F → RLE: count = cmd & 0x1F, fill = next byte
//	0x20..0x3F → short back-ref: offset = (cmd & 0x1F) + 1, length = 1
//	0x40..0x7F → literal run: count = 64 − (cmd & 0x3F)
//	0x80..0xFF → LZ: length = 18 − (cmd & 0x0F),
//	             offset = ((cmd & 0x70) << 4 | next_byte) + 1
//
// Modes 1, 3, 4: 8-bit control byte, MSB-first.
//
//	bit=1 → literal (mode 1/4 also advances dest ptr by 1 for word stride)
//	bit=0 → read match byte:
//	    bit7=1 → LZ (same encoding as mode 0)
//	    bit7=0, bit6=1 → RLE fill (count = match & 0x3F, fill = next byte)
//	    bit7=0, bit6=0, value=0 → EXIT
//	    bit7=0, bit6=0 → literal run (count = match & 0x3F)
//
// Mode 2: same as mode 0 but simpler dispatch (no short back-ref / long literal).
//
// Mode 5: table-relative dictionary; u16be table offset at payload start.
//
//	bit7=1 → emit byte from table at index (cmd & 0x7F); 0xFF terminates
//	bit7=0 → literal byte
func DecompressLZSculptured(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("lzsculptured: too short")
	}
	mode := int(binary.BigEndian.Uint16(src[0:2]))
	pos := 4

	read := func() (byte, bool) {
		if pos >= len(src) {
			return 0, false
		}
		b := src[pos]
		pos++
		return b, true
	}

	copyBack := func(out []byte, offset, length int) ([]byte, error) {
		if offset <= 0 || offset > len(out) {
			return nil, fmt.Errorf("lzsculptured: back-ref offset %d out of range (output %d)", offset, len(out))
		}
		start := len(out) - offset
		for i := 0; i < length; i++ {
			out = append(out, out[start+i])
		}
		return out, nil
	}

	var out []byte
	var err error

	switch mode {
	case 0:
		// Byte-command stream; 0x00 = terminator
		for {
			cmd, ok := read()
			if !ok || cmd == 0x00 {
				break
			}
			if cmd >= 0x80 {
				// LZ back-reference
				// length = 18 - (cmd & 0x0F), from 64-entry Duff table at BE78
				// offset = ((cmd & 0x70) << 4 | next_byte) + 1  (11-bit)
				next, ok2 := read()
				if !ok2 {
					return nil, fmt.Errorf("lzsculptured: mode 0 LZ: unexpected EOF")
				}
				length := 18 - int(cmd&0x0F)
				offset := (int(cmd&0x70)<<4 | int(next)) + 1
				out, err = copyBack(out, offset, length)
				if err != nil {
					return nil, err
				}
			} else if cmd >= 0x40 {
				// Literal run: count = 64 - (cmd & 0x3F), Duff table at BF24
				count := 64 - int(cmd&0x3F)
				for i := 0; i < count; i++ {
					b, ok2 := read()
					if !ok2 {
						return nil, fmt.Errorf("lzsculptured: mode 0 literal: unexpected EOF")
					}
					out = append(out, b)
				}
			} else if cmd >= 0x20 {
				// Short back-reference: 1 byte from (cmd & 0x1F) + 1 bytes back
				offset := int(cmd&0x1F) + 1
				out, err = copyBack(out, offset, 1)
				if err != nil {
					return nil, err
				}
			} else {
				// RLE: count = cmd & 0x1F, fill = next byte
				count := int(cmd & 0x1F)
				fill, ok2 := read()
				if !ok2 {
					return nil, fmt.Errorf("lzsculptured: mode 0 RLE: unexpected EOF")
				}
				for i := 0; i < count; i++ {
					out = append(out, fill)
				}
			}
		}

	case 1, 3, 4:
		// 8-bit control byte, MSB-first.
		// Mode 1 and 4 use word-stride output (skip every other byte for interleaved planes).
		wordStride := mode != 3
		for {
			ctrl, ok := read()
			if !ok {
				break
			}
			for bit := 0; bit < 8; bit++ {
				if ctrl&0x80 != 0 {
					// Literal
					b, ok2 := read()
					if !ok2 {
						return nil, fmt.Errorf("lzsculptured: mode %d literal: unexpected EOF", mode)
					}
					out = append(out, b)
					if wordStride {
						out = append(out, 0) // stride padding
					}
				} else {
					// Match byte
					match, ok2 := read()
					if !ok2 {
						break
					}
					if match&0x80 != 0 {
						// LZ back-reference (same encoding as mode 0)
						next, ok3 := read()
						if !ok3 {
							return nil, fmt.Errorf("lzsculptured: mode %d LZ: unexpected EOF", mode)
						}
						length := 18 - int(match&0x0F)
						offset := (int(match&0x70)<<4 | int(next)) + 1
						if wordStride {
							offset *= 2
						}
						out, err = copyBack(out, offset, length)
						if err != nil {
							return nil, err
						}
					} else if match&0x40 != 0 {
						// RLE fill
						count := int(match & 0x3F)
						fill, ok3 := read()
						if !ok3 {
							return nil, fmt.Errorf("lzsculptured: mode %d RLE: unexpected EOF", mode)
						}
						for i := 0; i < count; i++ {
							out = append(out, fill)
							if wordStride {
								out = append(out, fill)
							}
						}
					} else if match == 0 {
						return out, nil
					} else {
						// Literal run
						count := int(match & 0x3F)
						for i := 0; i < count; i++ {
							b, ok3 := read()
							if !ok3 {
								return nil, fmt.Errorf("lzsculptured: mode %d literal run: unexpected EOF", mode)
							}
							out = append(out, b)
							if wordStride {
								out = append(out, 0)
							}
						}
					}
				}
				ctrl <<= 1
			}
		}

	case 2:
		// Byte-command stream, simplified (no short back-ref / extended literal).
		// bit7=1 → LZ; bit7=0 → literal (read next byte directly)
		for {
			cmd, ok := read()
			if !ok || cmd == 0 {
				break
			}
			if cmd&0x80 != 0 {
				next, ok2 := read()
				if !ok2 {
					return nil, fmt.Errorf("lzsculptured: mode 2 LZ: unexpected EOF")
				}
				length := 18 - int(cmd&0x0F)
				offset := (int(cmd&0x70)<<4 | int(next)) + 1
				out, err = copyBack(out, offset, length)
				if err != nil {
					return nil, err
				}
			} else {
				b, ok2 := read()
				if !ok2 {
					return nil, fmt.Errorf("lzsculptured: mode 2 literal: unexpected EOF")
				}
				out = append(out, b)
			}
		}

	case 5:
		// Table-relative dictionary; u16be table offset at payload start.
		if pos+2 > len(src) {
			return nil, fmt.Errorf("lzsculptured: mode 5 table offset: unexpected EOF")
		}
		tableOff := int(binary.BigEndian.Uint16(src[pos : pos+2]))
		tableBase := pos + tableOff
		pos += 2
		for {
			cmd, ok := read()
			if !ok || cmd == 0xFF {
				break
			}
			if cmd&0x80 != 0 {
				idx := int(cmd & 0x7F)
				if tableBase+idx >= len(src) {
					return nil, fmt.Errorf("lzsculptured: mode 5 table index %d out of range", idx)
				}
				out = append(out, src[tableBase+idx])
			} else {
				out = append(out, cmd)
			}
		}

	default:
		return nil, fmt.Errorf("lzsculptured: unknown mode %d", mode)
	}

	return out, nil
}
