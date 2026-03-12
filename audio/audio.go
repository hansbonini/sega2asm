// Package audio converts Mega Drive audio segments.
// PCM → WAV  (reference: smd_alteredbeast/tools/pcm2wav)
// PSG → MIDI (SN76489 register stream → General MIDI)
package audio

import (
	"encoding/binary"
	"fmt"
	"math"
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

// ---------------------------------------------------------------------------
// PSG (SN76489) → MIDI
// ---------------------------------------------------------------------------

// PSGEvent represents a single register write to the SN76489 PSG chip.
type PSGEvent struct {
	Tick     uint32 // absolute tick
	Register byte   // 0-7 (channel*2 + type: 0=tone/noise, 1=volume)
	Value    uint16 // 10-bit tone period or 4-bit volume (0=max, 15=silence)
}

// PSGToMIDI converts a slice of PSG register events to a MIDI type-0 file.
// Ticks are in VGM-style (44100 Hz clock ÷ PSG clock / tickrate) or
// caller can normalise beforehand.
func PSGToMIDI(events []PSGEvent, path string, ticksPerQN uint16) error {
	if ticksPerQN == 0 {
		ticksPerQN = 480
	}

	// Map PSG channels 0-2 to MIDI channels 0-2; channel 3 (noise) → channel 9 (drums)
	midiChan := [4]byte{0, 1, 2, 9}

	// Build MIDI track
	var track []byte
	writeVarLen := func(v uint32) {
		var buf [4]byte
		n := 0
		buf[n] = byte(v & 0x7F)
		n++
		v >>= 7
		for v > 0 {
			buf[n] = byte(v&0x7F) | 0x80
			n++
			v >>= 7
		}
		for i := n - 1; i >= 0; i-- {
			track = append(track, buf[i])
		}
	}

	// Tempo: 120 BPM = 500000 µs per quarter note
	tempo := uint32(500000)
	track = append(track, 0x00)             // delta time 0
	track = append(track, 0xFF, 0x51, 0x03) // tempo meta
	track = append(track, byte(tempo>>16), byte(tempo>>8), byte(tempo))

	// Track PSG state
	type chState struct {
		period uint16
		vol    byte
		note   byte
		on     bool
	}
	var ch [4]chState
	for i := range ch {
		ch[i].vol = 15 // silence
	}

	prevTick := uint32(0)

	psgPeriodToMIDINote := func(period uint16) byte {
		if period == 0 {
			return 60
		}
		// SN76489 tone freq = clock / (32 * period), clock = 3.579545 MHz
		freq := 3579545.0 / (32.0 * float64(period))
		if freq < 8.0 {
			return 0
		}
		note := 12*math.Log2(freq/440.0) + 69
		if note < 0 {
			note = 0
		}
		if note > 127 {
			note = 127
		}
		return byte(note)
	}

	psgVolToMIDI := func(v byte) byte {
		// 0=loudest (127), 15=silent (0)
		if v >= 15 {
			return 0
		}
		return byte((15 - int(v)) * 127 / 15)
	}

	for _, ev := range events {
		dt := ev.Tick - prevTick
		prevTick = ev.Tick

		chIdx := ev.Register / 2
		isVol := ev.Register&1 == 1
		if chIdx > 3 {
			continue
		}

		c := midiChan[chIdx]
		deltaTicks := dt

		if isVol {
			newVol := byte(ev.Value & 0xF)
			oldVol := ch[chIdx].vol
			ch[chIdx].vol = newVol

			midiVol := psgVolToMIDI(newVol)
			oldMidiVol := psgVolToMIDI(oldVol)

			if oldMidiVol == 0 && midiVol > 0 {
				// Note on
				note := ch[chIdx].note
				writeVarLen(deltaTicks)
				track = append(track, 0x90|c, note, midiVol)
				ch[chIdx].on = true
			} else if midiVol == 0 && ch[chIdx].on {
				// Note off
				writeVarLen(deltaTicks)
				track = append(track, 0x80|c, ch[chIdx].note, 0)
				ch[chIdx].on = false
			} else if ch[chIdx].on {
				// Aftertouch
				writeVarLen(deltaTicks)
				track = append(track, 0xA0|c, ch[chIdx].note, midiVol)
			} else {
				writeVarLen(deltaTicks) // consume delta even if no event
				track = append(track, 0xFF, 0x01, 0x00) // empty text meta = noop
			}
		} else {
			// Tone period change
			period := ev.Value
			newNote := psgPeriodToMIDINote(period)
			ch[chIdx].period = period

			if ch[chIdx].on && newNote != ch[chIdx].note {
				// Slide: note off + note on
				writeVarLen(deltaTicks)
				track = append(track, 0x80|c, ch[chIdx].note, 0)
				writeVarLen(0)
				midiVol := psgVolToMIDI(ch[chIdx].vol)
				track = append(track, 0x90|c, newNote, midiVol)
			} else {
				writeVarLen(deltaTicks)
				track = append(track, 0xFF, 0x01, 0x00)
			}
			ch[chIdx].note = newNote
		}
	}

	// End of track
	writeVarLen(0)
	track = append(track, 0xFF, 0x2F, 0x00)

	// Assemble MIDI file
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("psg2midi: %w", err)
	}
	defer f.Close()

	writeU32BE := func(v uint32) { binary.Write(f, binary.BigEndian, v) }
	writeU16BE := func(v uint16) { binary.Write(f, binary.BigEndian, v) }

	// MThd
	f.WriteString("MThd")
	writeU32BE(6)          // header length
	writeU16BE(0)          // type 0
	writeU16BE(1)          // 1 track
	writeU16BE(ticksPerQN) // ticks/quarter

	// MTrk
	f.WriteString("MTrk")
	writeU32BE(uint32(len(track)))
	f.Write(track)

	return nil
}

// ParseVGMPSGEvents parses a minimal subset of VGM files to extract
// SN76489 PSG register write events. This allows PSGToMIDI to consume
// standard VGM files for conversion.
func ParseVGMPSGEvents(data []byte) ([]PSGEvent, error) {
	if len(data) < 0x40 {
		return nil, fmt.Errorf("vgm: too short")
	}
	if string(data[0:4]) != "Vgm " {
		return nil, fmt.Errorf("vgm: bad magic")
	}

	dataOffset := uint32(0x40)
	if len(data) > 0x34 {
		rel := binary.LittleEndian.Uint32(data[0x34:])
		if rel != 0 {
			dataOffset = 0x34 + rel
		}
	}

	var events []PSGEvent
	pos := int(dataOffset)
	tick := uint32(0)
	// Channel register write tracking: SN76489 latch
	var latch byte

	for pos < len(data) {
		cmd := data[pos]
		pos++
		switch cmd {
		case 0x50: // PSG write
			if pos >= len(data) { goto done }
			b := data[pos]; pos++
			if b&0x80 != 0 {
				// Latch/data byte
				latch = b
				ch := (b >> 5) & 0x03
				typ := (b >> 4) & 0x01
				val := uint16(b & 0x0F)
				events = append(events, PSGEvent{
					Tick:     tick,
					Register: ch*2 + typ,
					Value:    val,
				})
			} else {
				// Data byte for latched register
				ch := (latch >> 5) & 0x03
				typ := (latch >> 4) & 0x01
				val := uint16(b & 0x3F)
				events = append(events, PSGEvent{
					Tick:     tick,
					Register: ch*2 + typ,
					Value:    val,
				})
			}
		case 0x61: // Wait N samples
			if pos+1 >= len(data) { goto done }
			n := binary.LittleEndian.Uint16(data[pos:])
			pos += 2
			tick += uint32(n)
		case 0x62: // Wait 735 samples
			tick += 735
		case 0x63: // Wait 882 samples
			tick += 882
		case 0x66: // End of sound data
			goto done
		default:
			if cmd >= 0x70 && cmd <= 0x7F {
				tick += uint32(cmd&0xF) + 1
			} else if cmd >= 0x80 && cmd <= 0x8F {
				// YM2612 DAC + wait
				tick += uint32(cmd & 0xF)
				pos++ // skip data byte
			} else {
				// Skip 2-byte commands (best effort)
				pos++
			}
		}
	}
done:
	return events, nil
}
