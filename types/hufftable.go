package types

// HuffEntry stores one slot in a 256-entry fast Huffman lookup table.
type HuffEntry struct {
	BitsUsed int  // code length to consume (1..8)
	Symbol   byte // decoded symbol
}

// HuffTable256 is a 256-entry direct-mapped Huffman lookup table.
// For a code of length L, the table contains 2^(8-L) copies of that code's
// entry at consecutive indices starting at code << (8-L).
type HuffTable256 [256]HuffEntry

// BuildHuffTable256Canonical builds a table from canonical Huffman counts.
// counts[i] is the number of codes of length i (i = 1..8).
// symbols are listed in order: first all length-1 symbols, then length-2, etc.
func BuildHuffTable256Canonical(counts [9]int, symbols []byte) HuffTable256 {
	var table HuffTable256
	code := 0
	symIdx := 0
	for length := 1; length <= 8; length++ {
		for j := 0; j < counts[length]; j++ {
			if symIdx >= len(symbols) {
				break
			}
			adjust := 8 - length
			nEntries := 1 << uint(adjust)
			base := code << uint(adjust)
			for k := 0; k < nEntries; k++ {
				idx := base + k
				if idx < 256 {
					table[idx] = HuffEntry{length, symbols[symIdx]}
				}
			}
			symIdx++
			code++
		}
		code <<= 1
	}
	return table
}

// BuildHuffTable256Pairs builds a table from (codeLen, symbol) pairs
// written sequentially to fill all 256 slots.
// Each pair with code length L fills 2^(8-L) consecutive slots.
func BuildHuffTable256Pairs(pairs [][2]byte) HuffTable256 {
	var table HuffTable256
	writePos := 0
	for _, p := range pairs {
		codeLen := int(p[0])
		symbol := p[1]
		if codeLen < 1 || codeLen > 8 {
			continue
		}
		slotCount := 1 << uint(8-codeLen)
		for i := 0; i < slotCount && writePos < 256; i++ {
			table[writePos] = HuffEntry{codeLen, symbol}
			writePos++
		}
	}
	return table
}

// Decode peeks 8 bits from br, looks up the entry, and consumes the
// correct number of bits. Returns the decoded symbol.
func (t *HuffTable256) Decode(br *MSBWordBitReader) (byte, error) {
	code, err := br.Peek(8)
	if err != nil {
		return 0, err
	}
	entry := t[code]
	br.Consume(entry.BitsUsed)
	return entry.Symbol, nil
}
