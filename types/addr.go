// Package types defines shared data types used across sega2asm packages.
package types

// Addr is a ROM address. It is an alias for uint32 used for semantic clarity.
type Addr = uint32

// AddrRange is a contiguous ROM address range [Start, End).
type AddrRange struct {
	Start Addr
	End   Addr
}

// Size returns the number of bytes covered by the range.
func (r AddrRange) Size() uint32 {
	return r.End - r.Start
}

// Contains reports whether addr falls within [Start, End).
func (r AddrRange) Contains(addr Addr) bool {
	return addr >= r.Start && addr < r.End
}
