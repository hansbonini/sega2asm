package compress

import "fmt"

// DecompressLZHRefpack decompresses a RefPack stream (EA Canada, e.g. FIFA 97).
//
// The format is auto-detected from the flags byte:
//
//	0x10: byte-oriented LZSS variant
//	0x30: Huffman
//	0x32: Huffman + 1st-order byte delta un-filter
//	0x34: Huffman + 2nd-order byte delta un-filter
//
// Compressed data is identified by magic byte 0xFB at offset 0x01.
//
// Header layout:
//
//	byte[0] = flags
//	            bit 0: size-present flag
//	            bits[7:1] = format type >> 1
//	byte[1] = 0xFB (magic)
//	byte[2..4] = decompressed size (big-endian 24-bit)
func DecompressLZHRefpack(src []byte) ([]byte, error) {
	if len(src) < 5 {
		return nil, fmt.Errorf("lzhrefpack: input too short (%d bytes)", len(src))
	}
	if src[1] != 0xFB {
		return nil, fmt.Errorf("lzhrefpack: bad magic byte 0x%02X, expected 0xFB", src[1])
	}

	switch src[0] & 0xFE {
	case 0x10:
		return decompressRefpack10(src)
	case 0x30, 0x32, 0x34:
		return decompressRefpack30(src)
	default:
		return nil, fmt.Errorf("lzhrefpack: unsupported format 0x%02X", src[0]&0xFE)
	}
}

// decompressRefpack10 handles format 0x10 (byte-oriented LZSS).
//
// Token types:
//
//	2-byte SHORT MATCH  (byte1 bit7 = 0):
//	  num_literals  = byte1 & 0x03
//	  match_length  = ((byte1 >> 2) & 0x07) + 3
//	  match_offset  = ((byte1 & 0x60) << 3) | byte2
//
//	3-byte MEDIUM MATCH (byte1 bit7=1, bit6=0):
//	  num_literals  = (byte2 >> 6) & 0x03
//	  match_length  = (byte1 & 0x3F) + 4
//	  match_offset  = ((byte2 & 0x3F) << 8) | byte3
//
//	4-byte LARGE MATCH  (byte1 bits 7,6=1, bit5=0):
//	  num_literals  = byte1 & 0x03
//	  match_length  = (((byte1 & 0x0C) << 6) | byte4) + 5
//	  match_offset  = (((byte1 >> 4) & 0x01) << 16) | (byte2 << 8) | byte3
//
//	LITERAL RUN  (byte1 bits 7,6,5=1 and byte1 < 0xFC):
//	  literal_count = ((byte1 & 0x1F) + 1) * 4
//
//	END OF STREAM  (byte1 >= 0xFC):
//	  final_literal_count = byte1 & 0x03
func decompressRefpack10(src []byte) ([]byte, error) {
	decompSize := int(src[2])<<16 | int(src[3])<<8 | int(src[4])
	pos := 5
	out := make([]byte, 0, decompSize)

	copyLiterals := func(count int) error {
		if pos+count > len(src) {
			return fmt.Errorf("lzhrefpack: literal read past end of input at offset %d", pos)
		}
		out = append(out, src[pos:pos+count]...)
		pos += count
		return nil
	}

	copyMatch := func(length, matchOffset int) error {
		p := len(out) - 1 - matchOffset
		if p < 0 {
			return fmt.Errorf("lzhrefpack: match offset %d references before start of output (size %d)", matchOffset, len(out))
		}
		for i := 0; i < length; i++ {
			out = append(out, out[p])
			p++
		}
		return nil
	}

	for {
		if pos >= len(src) {
			return nil, fmt.Errorf("lzhrefpack: unexpected end of input")
		}
		b1 := src[pos]
		pos++

		// END OF STREAM
		if b1 >= 0xFC {
			if err := copyLiterals(int(b1 & 0x03)); err != nil {
				return nil, err
			}
			break
		}

		// LITERAL RUN (bits 7,6,5 all set, b1 < 0xFC)
		if b1 >= 0xE0 {
			if err := copyLiterals((int(b1&0x1F) + 1) * 4); err != nil {
				return nil, err
			}
			continue
		}

		// LARGE MATCH (bits 7,6=1, bit5=0)
		if b1 >= 0xC0 {
			if pos+3 > len(src) {
				return nil, fmt.Errorf("lzhrefpack: truncated large match token")
			}
			b2, b3, b4 := src[pos], src[pos+1], src[pos+2]
			pos += 3
			if err := copyLiterals(int(b1 & 0x03)); err != nil {
				return nil, err
			}
			if err := copyMatch((int(b1&0x0C)<<6|int(b4))+5, int(b1>>4&0x01)<<16|int(b2)<<8|int(b3)); err != nil {
				return nil, err
			}
			continue
		}

		// MEDIUM MATCH (bit7=1, bit6=0)
		if b1 >= 0x80 {
			if pos+2 > len(src) {
				return nil, fmt.Errorf("lzhrefpack: truncated medium match token")
			}
			b2, b3 := src[pos], src[pos+1]
			pos += 2
			if err := copyLiterals(int(b2>>6) & 0x03); err != nil {
				return nil, err
			}
			if err := copyMatch(int(b1&0x3F)+4, int(b2&0x3F)<<8|int(b3)); err != nil {
				return nil, err
			}
			continue
		}

		// SHORT MATCH (bit7=0)
		if pos >= len(src) {
			return nil, fmt.Errorf("lzhrefpack: truncated short match token")
		}
		b2 := src[pos]
		pos++
		if err := copyLiterals(int(b1 & 0x03)); err != nil {
			return nil, err
		}
		if err := copyMatch(int(b1>>2&0x07)+3, int(b1&0x60)<<3|int(b2)); err != nil {
			return nil, err
		}
	}

	if len(out) != decompSize {
		return nil, fmt.Errorf("lzhrefpack: header says %d bytes but decompressed %d", decompSize, len(out))
	}
	return out, nil
}

// refpackBitReader is the bit-stream reader for format 0x30 Huffman streams.
//
// 68k model: the stream is read in 16-bit big-endian words. Bits are delivered
// MSB-first using a 32-bit rotating shift register (d3).
type refpackBitReader struct {
	data     []byte
	pos      int
	prevWord uint16
	d3       uint32
	d1       int
}

func refpackRol32(v uint32, n int) uint32 {
	n &= 31
	return (v << n) | (v >> (32 - n))
}

func newRefpackBitReader(data []byte, pos int) *refpackBitReader {
	br := &refpackBitReader{data: data, pos: pos}
	if pos&1 != 0 {
		b := data[br.pos]
		br.pos++
		w := uint16(b) << 8
		br.d3 = refpackRol32(uint32(w)<<16|uint32(br.prevWord), 8)
		br.prevWord = w
		br.d1 = 0
	} else {
		w := uint16(data[br.pos])<<8 | uint16(data[br.pos+1])
		br.pos += 2
		br.d3 = refpackRol32(uint32(w)<<16|uint32(br.prevWord), 8)
		br.prevWord = w
		br.d1 = 8
	}
	return br
}

func (br *refpackBitReader) read(count int) int {
	d0 := br.d3 & 0xFF
	shifted := (d0 << count) & 0xFFFF
	result := (shifted >> 8) & 0xFF

	br.d1 -= count
	var rolCount int
	if br.d1 < 0 {
		w := uint16(br.data[br.pos])<<8 | uint16(br.data[br.pos+1])
		br.pos += 2
		br.d3 = uint32(w)<<16 | uint32(br.prevWord)
		br.prevWord = w
		br.d1 += 16
		rolCount = 16 - br.d1
	} else {
		rolCount = count
	}
	br.d3 = refpackRol32(br.d3, rolCount)
	return int(result)
}

func (br *refpackBitReader) readN(count int) int {
	if count <= 8 {
		return br.read(count)
	}
	hi := br.readN(count - 8)
	lo := br.read(8)
	return (hi << 8) | lo
}

func (br *refpackBitReader) readVlen() int {
	if br.d3&0x80 != 0 {
		v := br.read(3)
		return v & 3
	}
	d5 := 1
	d7 := 2
	for {
		bit := br.read(1)
		d7 *= 2
		d5++
		if bit != 0 {
			break
		}
	}
	raw := br.readN(d5)
	return raw + d7 - 4
}

// decompressRefpack30 handles formats 0x30, 0x32, 0x34
// (Huffman + optional delta post-processing).
func decompressRefpack30(src []byte) ([]byte, error) {
	fmt_ := src[0] & 0xFE

	br := newRefpackBitReader(src, 2)

	decompSize := br.readN(24)
	specialSym := br.read(8)

	// Build canonical Huffman code-length histogram
	var counts []int
	d5 := 1
	d7 := 0
	d2 := 0

	for {
		d7 <<= 1
		n := br.readVlen()
		d2 += n
		d7 += n
		counts = append(counts, n)

		testVal := d7
		if n == 0 {
			testVal = 0
		}
		rotated := ((testVal >> d5) | (testVal << (16 - d5))) & 0xFFFF
		if rotated&1 != 0 {
			break
		}
		d5++
	}

	maxLen := d5

	// Assign canonical Huffman codes to symbols
	totalSymbols := 0
	for _, c := range counts {
		totalSymbols += c
	}

	slotUsed := make([]bool, 256)
	symToSlot := make([]int, totalSymbols)
	slotPtr := 255

	for symCode := 0; symCode < totalSymbols; symCode++ {
		gap := br.readVlen()
		skipped := -1
		for skipped < gap {
			slotPtr = (slotPtr + 1) & 0xFF
			if !slotUsed[slotPtr] {
				skipped++
			}
		}
		slotUsed[slotPtr] = true
		symToSlot[symCode] = slotPtr
	}

	// Build canonical Huffman table
	type huffEntry struct {
		code   int
		length int
	}
	canon := make(map[huffEntry]int)
	code := 0
	symOrd := 0
	for length, cnt := range counts {
		bitLen := length + 1
		for j := 0; j < cnt; j++ {
			canon[huffEntry{code, bitLen}] = symToSlot[symOrd]
			symOrd++
			code++
		}
		code <<= 1
	}

	// Build fast lookup: 8-bit prefix -> (bitLength, outputByte)
	type fastEntry struct {
		bitLen int
		value  int
	}
	fast := make(map[int]fastEntry)
	for key, byteVal := range canon {
		if key.length <= 8 {
			step := 1 << (8 - key.length)
			prefix := key.code << (8 - key.length)
			for p := prefix; p < prefix+step; p++ {
				fast[p] = fastEntry{key.length, byteVal}
			}
		}
	}

	// Decompress
	out := make([]byte, 0, decompSize)
	for len(out) < decompSize {
		prefix8 := int(br.d3 & 0xFF)
		var actualByte int

		if entry, ok := fast[prefix8]; ok {
			actualByte = entry.value
			br.read(entry.bitLen)
		} else {
			acc := 0
			found := false
			for nbits := 1; nbits <= maxLen; nbits++ {
				acc = (acc << 1) | br.read(1)
				if val, ok := canon[huffEntry{acc, nbits}]; ok {
					actualByte = val
					found = true
					break
				}
			}
			if !found {
				return nil, fmt.Errorf("lzhrefpack: Huffman decode failed at output offset %d", len(out))
			}
		}

		if actualByte == specialSym {
			run := br.readVlen() - 1
			if run < 0 {
				control := br.read(1)
				if control == 0 {
					out = append(out, byte(br.read(8)))
				} else {
					break
				}
			} else {
				last := byte(0)
				if len(out) > 0 {
					last = out[len(out)-1]
				}
				for i := 0; i <= run; i++ {
					out = append(out, last)
				}
			}
		} else {
			out = append(out, byte(actualByte))
		}
	}

	// Delta post-processing
	if fmt_ == 0x32 || fmt_ == 0x34 {
		d0 := byte(0)
		d1 := byte(0)
		if fmt_ == 0x34 {
			for i := range out {
				d0 += out[i]
				d1 += d0
				out[i] = d1
			}
		} else {
			for i := range out {
				d0 += out[i]
				out[i] = d0
			}
		}
	}

	if len(out) != decompSize {
		return nil, fmt.Errorf("lzhrefpack: header says %d bytes but decompressed %d", decompSize, len(out))
	}
	return out, nil
}
