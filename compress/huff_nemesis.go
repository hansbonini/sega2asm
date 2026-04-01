package compress

import (
	"encoding/binary"
	"fmt"

	"sega2asm/types"
)

func init() {
	types.RegisterAlgorithm(types.Algorithm{Name: "huffnemesis", Family: types.FamilyHuffman, Description: "Nemesis tile compression; Huffman-coded nybble runs", Decompress: DecompressHuffNemesis})
	types.RegisterSignature(types.CompressSig{
		Name: "huffnemesis", WordAligned: true,
		Sig: []byte{
			0x3E, 0x06, 0x51, 0x47, 0x32, 0x05, 0xEE, 0x69, 0x0C, 0x01, 0x00, 0xFC, 0x64, 0x3E, 0x02, 0x41,
			0x00, 0xFF, 0xD2, 0x41, 0x10, 0x31, 0x10, 0x00, 0x48, 0x80, 0x9C, 0x40, 0x0C, 0x46, 0x00, 0x09,
			0x64, 0x06, 0x50, 0x46, 0xE1, 0x45, 0x1A, 0x18, 0x12, 0x31, 0x10, 0x01, 0x30, 0x01, 0x02, 0x41,
			0x00, 0x0F, 0x02, 0x40, 0x00, 0xF0, 0xE8, 0x48, 0xE9, 0x8C, 0x88, 0x01, 0x53, 0x43, 0x66, 0x06,
		},
	})
	types.RegisterSignature(types.CompressSig{
		Name: "huffnemesis", WordAligned: true,
		Sig: []byte{0x34, 0x18, 0xD4, 0x42, 0x64, 0x04, 0xD6, 0xFC, 0x00, 0x0A, 0xE5, 0x4A, 0x3A, 0x42, 0x76, 0x08, 0x74, 0x00, 0x78, 0x00},
	})
}

// DecompressHuffNemesis decompresses data using the Nemesis tile compression format.
//
// Header:
//
//	[0..1] big-endian word — bit 15: XOR mode flag; bits 14:0: tile count (0 = 256)
//	[2..]  codebook entries (variable-length, terminated by byte 0xFF)
//	[..]   Huffman-encoded bitstream
//
// Codebook entry encoding:
//
//	byte & 0x80 != 0  → set current nibble value to byte & 0x0F
//	byte & 0x80 == 0  → run_length = ((byte >> 4) & 7) + 1; code_bits = byte & 0x0F; next byte = Huffman code
//
// In XOR mode each output nibble is XOR'd with the preceding nibble.
// Reference: https://segaretro.org/Nemesis_compression
func DecompressHuffNemesis(src []byte) ([]byte, error) {
	if len(src) < 2 {
		return nil, fmt.Errorf("huffnemesis: data too short")
	}
	header := binary.BigEndian.Uint16(src[0:2])
	xorMode := (header & 0x8000) != 0
	totalTiles := int(header & 0x7FFF)
	pos := 2
	type nybbleRun struct{ codeBits, value, length byte }
	var runs [256]nybbleRun
	var curValue byte
	for pos < len(src) {
		b := src[pos]
		pos++
		if b == 0xFF {
			break
		}
		if b&0x80 != 0 {
			curValue = b & 0x0F
			continue
		}
		runLen := ((b >> 4) & 7) + 1
		codeBits := b & 0x0F
		if pos >= len(src) {
			break
		}
		code := src[pos]
		pos++
		if codeBits == 0 || codeBits > 8 {
			return nil, fmt.Errorf("huffnemesis: invalid code_bits=%d", codeBits)
		}
		idx := int(code) << (8 - int(codeBits))
		if idx >= 256 {
			return nil, fmt.Errorf("huffnemesis: code table index OOB")
		}
		runs[idx] = nybbleRun{codeBits: codeBits, value: curValue, length: runLen}
	}
	var bitsBuf byte
	bitsAvail := 0
	popBit := func() (int, bool) {
		bitsBuf <<= 1
		if bitsAvail == 0 {
			if pos >= len(src) {
				return 0, false
			}
			bitsBuf = src[pos]
			pos++
			bitsAvail = 8
		}
		bitsAvail--
		if bitsBuf&0x80 != 0 {
			return 1, true
		}
		return 0, true
	}
	popBits := func(n int) (int, bool) {
		v := 0
		for i := 0; i < n; i++ {
			b, ok := popBit()
			if !ok {
				return v, false
			}
			v = (v << 1) | b
		}
		return v, true
	}

	nw := types.NewNibbleWriter(totalTiles*8, xorMode)

	for !nw.Done() {
		code := 0
		var run *nybbleRun
		for n := 1; n <= 8; n++ {
			b, ok := popBit()
			if !ok {
				goto done
			}
			code = (code << 1) | b
			if n == 6 && code == 0x3F {
				runLen, ok1 := popBits(3)
				nyb, ok2 := popBits(4)
				if !ok1 || !ok2 {
					goto done
				}
				runLen++
				for i := 0; i < runLen; i++ {
					if nw.PutNibble(byte(nyb)) {
						goto done
					}
				}
				run = nil
				goto nextRun
			}
			idx := code << (8 - n)
			r := &runs[idx]
			if r.length != 0 && int(r.codeBits) == n {
				run = r
				break
			}
		}
		if run == nil {
			return nw.Bytes(), fmt.Errorf("huffnemesis: no code match")
		}
		for i := 0; i < int(run.length); i++ {
			if nw.PutNibble(run.value) {
				goto done
			}
		}
		continue
	nextRun:
	}
done:
	return nw.Bytes(), nil
}
