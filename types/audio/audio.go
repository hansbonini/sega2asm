// Package audio converts Mega Drive audio data to standard formats.
package audio

import (
	"encoding/binary"
	"fmt"
	"os"
)

// WriteWAVHeader writes a standard RIFF WAV header for 8-bit unsigned mono PCM.
// The header is written as a single 44-byte buffer.
func WriteWAVHeader(f *os.File, dataSize uint32, sampleRate int) error {
	var buf [44]byte
	copy(buf[0:4], "RIFF")
	binary.LittleEndian.PutUint32(buf[4:], 36+dataSize)
	copy(buf[8:12], "WAVE")
	copy(buf[12:16], "fmt ")
	binary.LittleEndian.PutUint32(buf[16:], 16)              // fmt chunk size
	binary.LittleEndian.PutUint16(buf[20:], 1)               // PCM format
	binary.LittleEndian.PutUint16(buf[22:], 1)               // mono
	binary.LittleEndian.PutUint32(buf[24:], uint32(sampleRate)) // sample rate
	binary.LittleEndian.PutUint32(buf[28:], uint32(sampleRate)) // byte rate (8-bit mono)
	binary.LittleEndian.PutUint16(buf[32:], 1)               // block align
	binary.LittleEndian.PutUint16(buf[34:], 8)               // bits per sample
	copy(buf[36:40], "data")
	binary.LittleEndian.PutUint32(buf[40:], dataSize)
	_, err := f.Write(buf[:])
	return err
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
