// Package rom handles loading and parsing Sega Mega Drive / Genesis ROMs.
package rom

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"
)

// Header represents the Mega Drive ROM header located at $000100-$0001FF.
type Header struct {
	SystemName   string // "SEGA MEGA DRIVE" or similar
	Copyright    string // Publisher / year
	DomesticName string // Japanese title
	OverseasName string // International title
	SerialType   string // Game type (GM = game, AI = AI type)
	Serial       string // Serial number
	Checksum     uint16 // ROM checksum
	DeviceSupport string // Supported IO devices
	ROMStart     uint32 // Start address of ROM data
	ROMEnd       uint32 // End address of ROM data
	RAMStart     uint32 // Start address of work RAM
	RAMEnd       uint32 // End address of work RAM
	SRAMInfo     string // Save RAM indicator
	SRAMStart    uint32 // Save RAM start
	SRAMEnd      uint32 // Save RAM end
	Notes        string // Modem / notes
	RegionCodes  string // Region support
}

// ROM holds the loaded ROM binary and its parsed header.
type ROM struct {
	Data   []byte
	Header *Header
	Size   int
}

// Load reads a Mega Drive ROM file, detecting interleaved formats.
func Load(path string) (*ROM, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading ROM %q: %w", path, err)
	}

	// Detect and de-interleave SMD format (512-byte header + interleaved blocks)
	if isSMD(data) {
		data, err = deSMD(data)
		if err != nil {
			return nil, fmt.Errorf("de-interleaving SMD: %w", err)
		}
	}

	r := &ROM{Data: data, Size: len(data)}
	r.Header = parseHeader(data)
	return r, nil
}

// isSMD detects a Super Magic Drive interleaved ROM.
func isSMD(data []byte) bool {
	if len(data) < 512 {
		return false
	}
	// SMD header magic: bytes 8-9 should be 0xAA 0xBB, or check for typical patterns
	if data[8] == 0xAA && data[9] == 0xBB {
		return true
	}
	return false
}

// deSMD de-interleaves an SMD-format ROM.
func deSMD(data []byte) ([]byte, error) {
	if len(data) < 512 {
		return nil, fmt.Errorf("SMD too small")
	}
	// Skip 512-byte header
	src := data[512:]
	out := make([]byte, len(src))

	blockSize := 0x4000
	for i := 0; i < len(src)/blockSize; i++ {
		block := src[i*blockSize : (i+1)*blockSize]
		// Odd bytes → first half, even bytes → second half
		half := blockSize / 2
		for j := 0; j < half; j++ {
			out[i*blockSize+j] = block[half+j]
			out[i*blockSize+half+j] = block[j]
		}
	}
	return out, nil
}

// parseHeader extracts the Mega Drive ROM header.
func parseHeader(data []byte) *Header {
	if len(data) < 0x200 {
		return &Header{}
	}

	h := &Header{}
	h.SystemName = strings.TrimRight(string(data[0x100:0x110]), " \x00")
	h.Copyright = strings.TrimRight(string(data[0x110:0x120]), " \x00")
	h.DomesticName = strings.TrimRight(string(data[0x120:0x150]), " \x00")
	h.OverseasName = strings.TrimRight(string(data[0x150:0x180]), " \x00")
	h.SerialType = strings.TrimRight(string(data[0x180:0x182]), " \x00")
	h.Serial = strings.TrimRight(string(data[0x182:0x18E]), " \x00")
	h.Checksum = binary.BigEndian.Uint16(data[0x18E:0x190])
	h.DeviceSupport = strings.TrimRight(string(data[0x190:0x1A0]), " \x00")
	h.ROMStart = binary.BigEndian.Uint32(data[0x1A0:0x1A4])
	h.ROMEnd = binary.BigEndian.Uint32(data[0x1A4:0x1A8])
	h.RAMStart = binary.BigEndian.Uint32(data[0x1A8:0x1AC])
	h.RAMEnd = binary.BigEndian.Uint32(data[0x1AC:0x1B0])
	h.SRAMInfo = strings.TrimRight(string(data[0x1B0:0x1BC]), " \x00")
	if len(data) >= 0x1C0 {
		h.Notes = strings.TrimRight(string(data[0x1BC:0x1F0]), " \x00")
		h.RegionCodes = strings.TrimRight(string(data[0x1F0:0x200]), " \x00")
	}
	return h
}

// Read8 reads a byte at offset.
func (r *ROM) Read8(offset uint32) byte {
	if int(offset) >= len(r.Data) {
		return 0
	}
	return r.Data[offset]
}

// Read16 reads a big-endian 16-bit value at offset.
func (r *ROM) Read16(offset uint32) uint16 {
	if int(offset)+2 > len(r.Data) {
		return 0
	}
	return binary.BigEndian.Uint16(r.Data[offset:])
}

// Read32 reads a big-endian 32-bit value at offset.
func (r *ROM) Read32(offset uint32) uint32 {
	if int(offset)+4 > len(r.Data) {
		return 0
	}
	return binary.BigEndian.Uint32(r.Data[offset:])
}

// Slice returns a slice of the ROM data at [start, end).
func (r *ROM) Slice(start, end uint32) []byte {
	if int(start) >= len(r.Data) {
		return nil
	}
	if int(end) > len(r.Data) {
		end = uint32(len(r.Data))
	}
	dst := make([]byte, end-start)
	copy(dst, r.Data[start:end])
	return dst
}

// PrintHeader prints a formatted ROM header summary.
func (r *ROM) PrintHeader() string {
	if r.Header == nil {
		return "(no header)"
	}
	h := r.Header
	return fmt.Sprintf(
		"  System    : %s\n  Copyright : %s\n  Domestic  : %s\n  Overseas  : %s\n"+
			"  Serial    : %s-%s\n  Checksum  : $%04X\n  ROM Range : $%06X-$%06X\n  Region    : %s",
		h.SystemName, h.Copyright, h.DomesticName, h.OverseasName,
		h.SerialType, h.Serial, h.Checksum,
		h.ROMStart, h.ROMEnd, h.RegionCodes,
	)
}
