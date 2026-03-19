package compress

import "fmt"

// westoneSPREAD[plane][nibble]: planar–chunky bit spread used by type-0x00 mode-2.
// SPREAD[p][n] = Σ(k=0..3) ((n>>k)&1) << (k*4+p)
// Each bit k of nibble n is placed at bit position (k*4+p) of a 16-bit word.
var westoneSPREAD = [4][16]uint16{
	{0, 1, 16, 17, 256, 257, 272, 273, 4096, 4097, 4112, 4113, 4352, 4353, 4368, 4369},
	{0, 2, 32, 34, 512, 514, 544, 546, 8192, 8194, 8224, 8226, 8704, 8706, 8736, 8738},
	{0, 4, 64, 68, 1024, 1028, 1088, 1092, 16384, 16388, 16448, 16452, 17408, 17412, 17472, 17476},
	{0, 8, 128, 136, 2048, 2056, 2176, 2184, 32768, 32776, 32896, 32904, 34816, 34824, 34944, 34952},
}

// westoneBR is the bit reader for type-0x02 (loc_18E7A).
//
// 68000 model: d0 = current shift byte (MSB-first), d1 = bits remaining.
// Initialisation: load first byte, discard bit 7 (add.b d0,d0), d1=7.
// read_bit(): d1--; if d1<0 reload; return old MSB, shift left.
type westoneBR struct {
	data []byte
	pos  int
	d0   byte
	d1   int
}

func newWestoneBR(data []byte) *westoneBR {
	br := &westoneBR{data: data}
	br.d0 = data[br.pos]
	br.pos++
	br.d0 <<= 1 // discard bit 7
	br.d1 = 7
	return br
}

func (br *westoneBR) readBit() int {
	br.d1--
	if br.d1 < 0 {
		br.d0 = br.data[br.pos]
		br.pos++
		br.d1 = 7
	}
	bit := int(br.d0 >> 7)
	br.d0 <<= 1
	return bit
}

// readRawSymbol (sub_18F2E):
//
//	leading 0 → read 8 bits → return 0x000..0x0FF
//	leading 1 → read 5 bits → return 0x100..0x11F
func (br *westoneBR) readRawSymbol() int {
	if br.readBit() == 0 {
		v := 0
		for i := 0; i < 8; i++ {
			v = (v << 1) | br.readBit()
		}
		return v
	}
	v := 0
	for i := 0; i < 5; i++ {
		v = (v << 1) | br.readBit()
	}
	return 0x100 | v
}

// westoneNode is one node in the Huffman tree.
// left/right ≥ 0 → leaf (symbol value); < 0 → internal node index = -(val+1).
type westoneNode struct{ left, right int }

// buildWestoneTree reads the Huffman tree from the bit stream (loc_18E7A phase 1).
//
// Tree encoding: bit=1 → internal node, bit=0 → leaf (followed by readRawSymbol).
// d2 tracks whether the next slot is left (d2=0) or right (d2≠0).
// A stack records parent indices to fill right children after subtrees complete.
func buildWestoneTree(br *westoneBR) []westoneNode {
	nodes := []westoneNode{{-1, -1}} // node 0 = root
	stack := []int{}
	d2 := 0
	cur := 0

	for {
		if br.readBit() != 0 {
			// Internal node
			nxt := len(nodes)
			nodes = append(nodes, westoneNode{-1, -1})
			if d2 == 0 {
				stack = append(stack, cur)
				nodes[cur].left = -(nxt + 1)
				// d2 stays 0; new node fills its left child first
			} else {
				nodes[cur].right = -(nxt + 1)
				d2 = 0 // entering right-child internal node; fill its left first
			}
			cur = nxt
		} else {
			// Leaf
			sym := br.readRawSymbol()
			if d2 == 0 {
				nodes[cur].left = sym
				d2 = 2 // left done; next slot is right
			} else {
				nodes[cur].right = sym
				if len(stack) == 0 {
					break
				}
				cur = stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				// d2 stays nonzero; parent now fills its right child
			}
		}
	}
	return nodes
}

// decodeWestoneSym traverses the Huffman tree and returns the symbol.
// Escape symbol 0x11F → return a fresh readRawSymbol instead.
func decodeWestoneSym(br *westoneBR, nodes []westoneNode) int {
	node := 0
	for {
		var child int
		if br.readBit() == 0 {
			child = nodes[node].left
		} else {
			child = nodes[node].right
		}
		if child < 0 {
			node = -(child + 1)
		} else {
			if child == 0x11F {
				return br.readRawSymbol()
			}
			return child
		}
	}
}

// DecompressLZWestone decompresses Monster World IV graphics data
// using the Huffman + LZ scheme (loc_18E7A, type 0x02).
//
// Symbols:
//
//	0x000..0x0FF → literal byte
//	0x100..0x11F → back-reference: length = sym−0xFD (3..34),
//	               next symbol = back-offset (1..288 bytes back)
//
// Output is always 1024 bytes (32 Genesis tiles × 32 bytes).
func DecompressLZWestone(src []byte) ([]byte, error) {
	if len(src) < 1 {
		return nil, fmt.Errorf("lzwestone: empty input")
	}
	br := newWestoneBR(src)
	nodes := buildWestoneTree(br)

	out := make([]byte, 0, 0x400)
	d2 := 0x3FF // decremented per emitted byte; loop while d2 >= 0

	for d2 >= 0 {
		sym := decodeWestoneSym(br, nodes)
		if sym < 0x100 {
			out = append(out, byte(sym))
			d2--
		} else {
			length := sym - 0xFD // 3..34
			d2 -= length
			off := decodeWestoneSym(br, nodes) // 0..0x11F
			srcOff := len(out) - off - 1
			if srcOff < 0 {
				return nil, fmt.Errorf("lzwestone: back-reference out of bounds (off=%d, len=%d)", off, len(out))
			}
			for i := 0; i < length; i++ {
				out = append(out, out[srcOff+i])
			}
		}
	}
	if len(out) > 0x400 {
		out = out[:0x400]
	}
	return out, nil
}

// DecompressLZWestoneBlock decompresses Monster World IV graphics data
// using the block-based scheme (loc_18CD2, type 0x00).
//
// Outer loop: 32 blocks × 32 bytes = 1024 bytes.
// Each block begins with a control byte selecting one of three modes:
//
//	ctrl == 0x00        → mode 0: 32 literal bytes
//	ctrl  < 0x80        → mode 1: sparse bitmap (ctrl = number of color groups)
//	ctrl >= 0x80        → mode 2: tile-row encoding with XOR + planar bit-spread
func DecompressLZWestoneBlock(src []byte) ([]byte, error) {
	pos := 0
	out := make([]byte, 0, 0x400)

	rb := func() byte {
		b := src[pos]
		pos++
		return b
	}

	for block := 0; block < 32; block++ {
		ctrl := rb()

		switch {
		case ctrl == 0x00:
			// Mode 0: 32 literal bytes
			for i := 0; i < 32; i++ {
				out = append(out, rb())
			}

		case ctrl < 0x80:
			// Mode 1: sparse bitmap.
			// ctrl = number of color groups; each group: color byte + 4-byte MSB-first bitmap.
			// combinedMask tracks which of the 32 pixel positions were covered.
			// Positions not covered by any group are filled with literal bytes.
			var blockData [32]byte
			var combinedMask uint32

			for i := 0; i < int(ctrl); i++ {
				color := rb()
				bm := uint32(rb())<<24 | uint32(rb())<<16 | uint32(rb())<<8 | uint32(rb())
				combinedMask |= bm
				tmp, p := bm, 0
				for tmp != 0 {
					if tmp&0x80000000 != 0 {
						blockData[p] = color
					}
					tmp <<= 1
					p++
				}
			}

			// Literal fill for positions not covered
			inv, p := ^combinedMask, 0
			for inv != 0 {
				if inv&0x80000000 != 0 {
					blockData[p] = rb()
				}
				inv <<= 1
				p++
			}
			out = append(out, blockData[:]...)

		default:
			// Mode 2: tile-row encoding.
			// ctrl bits 0-3: XOR-enable per pass.
			// next byte d1: 2-bit pairs per pass (bit0=base color, bit1=solid flag).
			d0 := uint32(ctrl)
			d1 := uint32(rb())
			var ws [32]byte // 4 rows × 8 bytes workspace
			wsRow := 0

			for pass := 0; pass < 4; pass++ {
				baseColor := byte(0x00)
				if d1&1 != 0 {
					baseColor = 0xFF
				}
				d1 >>= 1
				solid := (d1 & 1) != 0
				d1 >>= 1

				if solid {
					for i := 0; i < 8; i++ {
						ws[wsRow+i] = baseColor
					}
				} else {
					// Selective: bitmap byte LSB-first; 0=base_color, 1=read explicit
					bm := rb()
					for i := 0; i < 8; i++ {
						if bm&1 != 0 {
							ws[wsRow+i] = rb()
						} else {
							ws[wsRow+i] = baseColor
						}
						bm >>= 1
					}
				}

				// XOR prefix-chain if enabled for this pass
				if d0&1 != 0 {
					acc := ws[wsRow]
					for i := 1; i < 8; i++ {
						acc ^= ws[wsRow+i]
						ws[wsRow+i] = acc
					}
				}
				d0 >>= 1
				wsRow += 8
			}

			// Bit-spread: 32-byte workspace → 8 output longwords (32 bytes).
			// For each column col (0..7):
			//   Gather ws[col], ws[col+8], ws[col+16], ws[col+24].
			//   Low nibbles → SPREAD → high word (pixels 0-3).
			//   High nibbles → SPREAD → low word (pixels 4-7).
			//   Emit as big-endian uint32.
			for col := 0; col < 8; col++ {
				ws0, ws1 := ws[col], ws[col+8]
				ws2, ws3 := ws[col+16], ws[col+24]

				lo := [4]byte{ws0 & 0xF, ws1 & 0xF, ws2 & 0xF, ws3 & 0xF}
				hi := [4]byte{ws0 >> 4, ws1 >> 4, ws2 >> 4, ws3 >> 4}

				hw := uint32(westoneSPREAD[0][lo[0]]) | uint32(westoneSPREAD[1][lo[1]]) |
					uint32(westoneSPREAD[2][lo[2]]) | uint32(westoneSPREAD[3][lo[3]])
				lw := uint32(westoneSPREAD[0][hi[0]]) | uint32(westoneSPREAD[1][hi[1]]) |
					uint32(westoneSPREAD[2][hi[2]]) | uint32(westoneSPREAD[3][hi[3]])

				v := (hw << 16) | lw
				out = append(out, byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
			}
		}
	}
	return out, nil
}
