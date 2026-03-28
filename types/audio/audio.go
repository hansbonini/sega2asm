// Package audio converts Mega Drive audio data to standard formats.
package audio

import (
	"encoding/binary"
	"fmt"
	"os"
)

// Encoder converts raw audio data and writes to the given path.
type Encoder interface {
	Name() string
	Ext() string
	Encode(data []byte, path string, sampleRate int) error
}

// encoders maps name → encoder implementation.
var encoders = map[string]Encoder{}

// RegisterEncoder registers an audio encoder by name.
func RegisterEncoder(e Encoder) { encoders[e.Name()] = e }

// Get returns the encoder for the given name, or nil.
func Get(name string) Encoder { return encoders[name] }

// WAV returns the WAV encoder (convenience shortcut).
func WAV() Encoder { return encoders["wav"] }

// WriteWAVHeader writes a standard RIFF WAV header for 8-bit unsigned mono PCM.
func WriteWAVHeader(f *os.File, dataSize uint32, sampleRate int) error {
	writeStr := func(s string) { f.WriteString(s) }
	writeU32 := func(v uint32) { binary.Write(f, binary.LittleEndian, v) }
	writeU16 := func(v uint16) { binary.Write(f, binary.LittleEndian, v) }

	writeStr("RIFF")
	writeU32(36 + dataSize)
	writeStr("WAVE")
	writeStr("fmt ")
	writeU32(16)                 // fmt chunk size
	writeU16(1)                  // PCM format
	writeU16(1)                  // mono
	writeU32(uint32(sampleRate)) // sample rate
	writeU32(uint32(sampleRate)) // byte rate (8-bit mono)
	writeU16(1)                  // block align
	writeU16(8)                  // bits per sample
	writeStr("data")
	writeU32(dataSize)
	return nil
}

// DefaultSampleRate is the typical Mega Drive PCM sample rate.
const DefaultSampleRate = 7040

// NormalizeSampleRate returns the given rate, or DefaultSampleRate if <= 0.
func NormalizeSampleRate(rate int) int {
	if rate <= 0 {
		return DefaultSampleRate
	}
	return rate
}

// WritePCMAsWAV is a convenience function that writes raw PCM data as a WAV file.
func WritePCMAsWAV(data []byte, path string, sampleRate int) error {
	sampleRate = NormalizeSampleRate(sampleRate)
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("pcm2wav: %w", err)
	}
	defer f.Close()

	if err := WriteWAVHeader(f, uint32(len(data)), sampleRate); err != nil {
		return err
	}
	_, err = f.Write(data)
	return err
}
