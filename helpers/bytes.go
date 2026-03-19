package helpers

import "encoding/binary"

// ReadBEU16 reads a big-endian uint16 from data at byte offset pos.
// Returns 0 if pos would read past the end of data.
func ReadBEU16(data []byte, pos int) uint16 {
	if pos+2 > len(data) {
		return 0
	}
	return binary.BigEndian.Uint16(data[pos:])
}

// ReadBEU32 reads a big-endian uint32 from data at byte offset pos.
// Returns 0 if pos would read past the end of data.
func ReadBEU32(data []byte, pos int) uint32 {
	if pos+4 > len(data) {
		return 0
	}
	return binary.BigEndian.Uint32(data[pos:])
}
