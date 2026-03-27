package compress

import (
	"encoding/binary"
	"fmt"
)

// DecompressExpGolombClimax decompresses tile graphics using the Climax/Camelot
// format found in Shining Force 1 and related titles.
//
// Unlike lz77climax (Landstalker LZSS), this is a specialised 4bpp tile
// graphics compressor that encodes nibble values with 2-D spatial
// navigation and produces tile-ordered VDP output.
//
// Stream layout:
//
//	byte 0 : widthTiles  (image width  in 8-pixel tile columns, must be multiple of 4)
//	byte 1 : heightTiles (image height in 8-pixel tile rows,    must be multiple of 4)
//	byte 2+: packed bitstream
//
// The decompressor runs three phases:
//  1. Decode the bitstream into a nibble buffer (one nibble per byte, flagged 0x80).
//  2. Pack adjacent nibble pairs into bytes (two pixels per byte, high|low nibble).
//  3. Rearrange the packed bitmap into VDP tile order (4×4 tile groups).
func DecompressExpGolombClimax(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("expgolombclimax: input too short")
	}

	widthTiles := int(src[0])
	heightTiles := int(src[1])
	stride := widthTiles * 8 // row width in nibble-buffer bytes
	bufSize := stride * heightTiles * 8

	if bufSize == 0 {
		return nil, fmt.Errorf("expgolombclimax: zero dimensions")
	}
	if widthTiles%4 != 0 || heightTiles%4 != 0 {
		return nil, fmt.Errorf("expgolombclimax: dimensions %dx%d must be multiples of 4",
			widthTiles, heightTiles)
	}

	// ---- bitstream reader ------------------------------------------------
	pos := 2
	var d0 uint16
	bitsLeft := 0

	readBit := func() int {
		bitsLeft--
		if bitsLeft < 0 {
			bitsLeft = 15
			if pos+1 < len(src) {
				d0 = binary.BigEndian.Uint16(src[pos:])
			} else {
				d0 = 0
			}
			pos += 2
		}
		b := int(d0 >> 15)
		d0 <<= 1
		return b
	}

	// ---- Phase 1: bitstream → nibble buffer ------------------------------
	nibBuf := make([]byte, bufSize+2) // +2 for end sentinel
	cursor := 0

	writeNib := func(p int, v byte) {
		if p >= 0 && p < bufSize {
			nibBuf[p] = v
		}
	}

mainLoop:
	for {
		// Exp-Golomb position delta: count leading 0-bits (unary prefix)
		unary := 0
		for readBit() == 0 {
			unary++
			if unary > 24 {
				return nil, fmt.Errorf("expgolombclimax: corrupt bitstream (unary overflow)")
			}
		}
		cursor += (2 << uint(unary)) - 2

		// Read (unary+1) additional offset bits
		extra := 0
		for i := 0; i <= unary; i++ {
			extra = (extra << 1) | readBit()
		}
		cursor += extra

		if cursor >= bufSize {
			break
		}

		// Read 4-bit nibble value
		nib := 0
		for i := 0; i < 4; i++ {
			nib = (nib << 1) | readBit()
		}
		val := byte(nib) | 0x80
		writeNib(cursor, val)

		// Continue bit: 0 = new position, 1 = spatial navigation
		if readBit() == 0 {
			continue
		}

		// Direction navigation — replicate the same nibble along a path.
		// Prefix code: 1b → down+b, 01 → down-1, 001d → down±2, 000 → end.
		dp := cursor
		for {
			a := readBit()
			if a == 1 {
				dp += stride + readBit()
			} else if readBit() == 1 {
				dp += stride - 1
			} else if readBit() == 0 {
				continue mainLoop
			} else if readBit() == 1 {
				dp += stride + 2
			} else {
				dp += stride - 2
			}
			if dp < 0 || dp >= bufSize {
				continue mainLoop
			}
			writeNib(dp, val)
		}
	}

	// ---- Phase 2: pack nibble pairs into bytes ---------------------------
	// Each flagged byte (0x8n) holds one nibble n; unflagged (0x00) means
	// "not written" and inherits from the previous value.
	nibBuf[bufSize] = 0x80
	nibBuf[bufSize+1] = 0x80 // sentinel pair

	packed := make([]byte, 0, bufSize/2)
	var fill byte // repeat / fill byte (d4 in the original ASM)

	for i := 0; i < bufSize; i += 2 {
		hi, lo := nibBuf[i], nibBuf[i+1]

		// Zero word → repeat previous fill byte
		if hi == 0 && lo == 0 {
			packed = append(packed, fill)
			continue
		}

		var out byte
		switch {
		case hi >= 0x80 && lo >= 0x80:
			// Both nibbles explicitly set
			hn, ln := hi&0x0F, lo&0x0F
			out = (hn << 4) | ln
			if out == 0 {
				goto phase3 // end sentinel
			}
			fill = (ln << 4) | ln

		case hi >= 0x80:
			// Only high nibble set → duplicate it
			n := hi & 0x0F
			out = (n << 4) | n
			fill = out

		default:
			// High nibble inherits from previous fill, low nibble from buffer
			ln := lo & 0x0F
			out = (fill & 0xF0) | ln
			fill = (ln << 4) | ln
		}

		packed = append(packed, out)
	}

phase3:
	// ---- Phase 3: rearrange packed bitmap into VDP tile order -------------
	// The packed image is a flat bitmap (widthTiles*4 bytes per row).
	// Rearrange into 32-byte tiles grouped in 4×4 blocks.
	packedStride := widthTiles * 4 // bytes per row in packed image
	out := make([]byte, 0, widthTiles*heightTiles*32)

	for cg := 0; cg < widthTiles; cg += 4 {
		for rg := 0; rg < heightTiles; rg += 4 {
			for c := 0; c < 4; c++ {
				col := cg + c
				for r := 0; r < 4; r++ {
					row := rg + r
					for py := 0; py < 8; py++ {
						off := (row*8+py)*packedStride + col*4
						for px := 0; px < 4; px++ {
							if off+px < len(packed) {
								out = append(out, packed[off+px])
							} else {
								out = append(out, 0)
							}
						}
					}
				}
			}
		}
	}

	return out, nil
}
