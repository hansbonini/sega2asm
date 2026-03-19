// Package disasm defines common types shared by all CPU disassemblers.
package disasm

import "sega2asm/types"

// BaseResult holds the fields common to every disassembler result.
// CPU-specific result types embed this struct and add any extra fields.
type BaseResult struct {
	Addr    uint32
	Bytes   []byte
	Text    string
	IsValid bool
}

// Cursor holds the read-only state common to all disassemblers:
// the binary data, a base address, a label map, and the current byte position.
// Embed Cursor in a CPU-specific Disassembler struct to inherit PC and Remaining.
type Cursor struct {
	Data   []byte
	Base   uint32
	Labels types.LabelMap
	Pos    int
}

// PC returns the current program counter value (Base + Pos).
func (c *Cursor) PC() uint32 { return c.Base + uint32(c.Pos) }

// Remaining returns the number of unread bytes.
func (c *Cursor) Remaining() int { return len(c.Data) - c.Pos }
