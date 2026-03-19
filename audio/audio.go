// Package audio converts Mega Drive audio segments.
// PCM → WAV  (reference: smd_alteredbeast/tools/pcm2wav)
package audio

import (
	"encoding/binary"
	"fmt"
	"os"
)

// ---------------------------------------------------------------------------
// PCM → WAV
// ---------------------------------------------------------------------------

// PCMToWAV writes a standard 8-bit unsigned mono WAV from raw PCM bytes.
// sampleRate is typically 7040 Hz for Mega Drive (or 8000 Hz for some games).
func PCMToWAV(data []byte, path string, sampleRate int) error {
	if sampleRate <= 0 {
		sampleRate = 7040
	}
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("pcm2wav: %w", err)
	}
	defer f.Close()

	dataSize := uint32(len(data))
	// WAV RIFF header
	writeStr := func(s string) { f.WriteString(s) }
	writeU32 := func(v uint32) { binary.Write(f, binary.LittleEndian, v) }
	writeU16 := func(v uint16) { binary.Write(f, binary.LittleEndian, v) }

	writeStr("RIFF")
	writeU32(36 + dataSize) // chunk size
	writeStr("WAVE")
	writeStr("fmt ")
	writeU32(16)                    // fmt chunk size
	writeU16(1)                     // PCM
	writeU16(1)                     // mono
	writeU32(uint32(sampleRate))
	writeU32(uint32(sampleRate))    // byte rate (8-bit mono)
	writeU16(1)                     // block align
	writeU16(8)                     // bits per sample
	writeStr("data")
	writeU32(dataSize)

	_, err = f.Write(data)
	return err
}
