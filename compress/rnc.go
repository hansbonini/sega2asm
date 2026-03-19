package compress

import (
	"encoding/binary"
	"fmt"
	"sort"
)

// ── RNC — Rob Northen Compression  (Method 1 & 2) ────────────────────────────
//
// 18-byte header:
//   [0..2]  "RNC"
//   [3]     method (0x01 or 0x02)
//   [4..7]  unpacked size  BE32
//   [8..11] packed size    BE32
//   [12..13] unpacked CRC16 (not verified)
//   [14..15] packed CRC16  (not verified)
//   [16]    leeway
//   [17]    pack_chunks  (Method 1 only)

// rncBR is a byte-by-byte bit reader that pops from LSB first.
type rncBR struct {
	src   []byte
	pos   int
	buf   uint64
	avail int
}

func (r *rncBR) fill() {
	for r.avail <= 56 && r.pos < len(r.src) {
		r.buf |= uint64(r.src[r.pos]) << uint(r.avail)
		r.pos++
		r.avail += 8
	}
}
func (r *rncBR) pop(n int) int {
	if n == 0 {
		return 0
	}
	r.fill()
	v := int(r.buf & ((1 << uint(n)) - 1))
	r.buf >>= uint(n)
	r.avail -= n
	return v
}
func (r *rncBR) alignByte() {
	if r.avail%8 != 0 {
		r.pop(r.avail % 8)
	}
}

type rncHuff struct{ revCode, length, symbol int }

func buildRNCTable(br *rncBR) []rncHuff {
	n := br.pop(5)
	if n == 0 {
		return nil
	}
	lengths := make([]int, n)
	for i := range lengths {
		lengths[i] = br.pop(4)
	}
	type e struct{ length, index int }
	var entries []e
	for i, l := range lengths {
		if l > 0 {
			entries = append(entries, e{l, i})
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].length != entries[j].length {
			return entries[i].length < entries[j].length
		}
		return entries[i].index < entries[j].index
	})
	codes := make([]rncHuff, len(entries))
	code, prevLen := 0, 0
	for i, e := range entries {
		if prevLen > 0 {
			code++
			if e.length > prevLen {
				code <<= uint(e.length - prevLen)
			}
		}
		rev, c := 0, code
		for j := 0; j < e.length; j++ {
			rev = (rev << 1) | (c & 1)
			c >>= 1
		}
		codes[i] = rncHuff{revCode: rev, length: e.length, symbol: e.index}
		prevLen = e.length
	}
	return codes
}

func decodeRNC(br *rncBR, table []rncHuff) int {
	if len(table) == 0 {
		return 0
	}
	maxLen := 0
	for _, c := range table {
		if c.length > maxLen {
			maxLen = c.length
		}
	}
	acc := 0
	for n := 1; n <= maxLen; n++ {
		acc |= br.pop(1) << (n - 1)
		for _, c := range table {
			if c.length == n && c.revCode == acc {
				return c.symbol
			}
		}
	}
	return 0
}

// DecompressRNC1 decompresses RNC Method 1 (Huffman + LZ).
func DecompressRNC1(src []byte) ([]byte, error) {
	if len(src) < 18 {
		return nil, fmt.Errorf("rnc1: header too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' || src[3] != 0x01 {
		return nil, fmt.Errorf("rnc1: bad magic/method")
	}
	unpackedSize := int(binary.BigEndian.Uint32(src[4:8]))
	chunks := int(src[17])
	br := &rncBR{src: src, pos: 18}
	out := make([]byte, 0, unpackedSize)
	for ch := 0; ch < chunks; ch++ {
		br.alignByte()
		rawTable := buildRNCTable(br)
		posTable := buildRNCTable(br)
		lenTable := buildRNCTable(br)
		numCmds := br.pop(16)
		for cmd := 0; cmd <= numCmds; cmd++ {
			rawCount := decodeRNC(br, rawTable)
			for i := 0; i < rawCount; i++ {
				out = append(out, byte(br.pop(8)))
			}
			if cmd < numCmds {
				dist := decodeRNC(br, posTable) + 1
				copyLen := decodeRNC(br, lenTable) + 2
				copyDist(&out, dist, copyLen)
			}
		}
	}
	if len(out) > unpackedSize {
		out = out[:unpackedSize]
	}
	return out, nil
}

// DecompressRNC2 decompresses RNC Method 2 (variable-length LZ, no Huffman).
// Stream after header: 2 bits initial raw count; then loop: dist bits, back-ref, raw count bits.
func DecompressRNC2(src []byte) ([]byte, error) {
	if len(src) < 18 {
		return nil, fmt.Errorf("rnc2: header too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' || src[3] != 0x02 {
		return nil, fmt.Errorf("rnc2: bad magic/method")
	}
	unpackedSize := int(binary.BigEndian.Uint32(src[4:8]))
	br := &rncBR{src: src, pos: 18}
	out := make([]byte, 0, unpackedSize)
	readRaw := func(n int) {
		for i := 0; i < n; i++ {
			out = append(out, byte(br.pop(8)))
		}
	}
	readRaw(br.pop(2)) // initial raw bytes
	for len(out) < unpackedSize {
		var d int
		if br.pop(1) == 0 {
			d = br.pop(8)
		} else {
			d = br.pop(14)
		}
		if d == 0 {
			break
		}
		count := br.pop(4) + 2
		copyDist(&out, d, count)
		switch br.pop(2) {
		case 1:
			readRaw(1)
		case 2:
			readRaw(2)
		case 3:
			readRaw(br.pop(8))
		}
	}
	if len(out) > unpackedSize {
		out = out[:unpackedSize]
	}
	return out, nil
}

// DecompressRNC auto-detects Method 1 or 2 from the header.
func DecompressRNC(src []byte) ([]byte, error) {
	if len(src) < 4 {
		return nil, fmt.Errorf("rnc: too short")
	}
	if src[0] != 'R' || src[1] != 'N' || src[2] != 'C' {
		return nil, fmt.Errorf("rnc: bad magic")
	}
	switch src[3] {
	case 0x01:
		return DecompressRNC1(src)
	case 0x02:
		return DecompressRNC2(src)
	default:
		return nil, fmt.Errorf("rnc: unknown method 0x%02X", src[3])
	}
}
