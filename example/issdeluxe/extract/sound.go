package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

// The sound driver ($1FD954) runs on the 68000. FM and PSG writes go through
// queues in Z80 RAM ($0200 part 1, $0300 part 2, $0400 PSG) that the Z80
// program drains; PCM is mixed in software: two voices of signed 8-bit
// samples, each with a loop region and an 8-bit rate step, summed with
// saturation into a 400-byte ring buffer at Z80 $0504 that the Z80 plays
// through the YM2612 DAC, one byte every 384 Z80 cycles.
//
// Music and effects are scripts of 4-byte events [command, argument, word]
// (music bank table 0, 1024 scripts; a script starts with its priority byte
// and $FF, and the argument of its first event is its hardware channel). Effect n (sound_play_sfx) is entry n of
// table 2: [n, priority, duration.w, script.w] with script = $300 + n.
const (
	pcmBank     = 0x1613EC
	pcmBankEnd  = 0x1EB45C
	musicBank   = 0x1EB45C
	pcmSets     = 0x1FFB88 // word offsets (from here) of windows into pcmList
	pcmList     = 0x1FFBD8 // sorted long offsets of the samples in pcmBank
	pcmListEnd  = 0x1FFD34
	numPCMSets  = 31
	numScripts  = 1024
	numSfx      = 126
	numSongs    = 26
	dacCycles   = 384 // Z80 cycles per DAC byte
	z80ClockPAL = 3546894.0
	z80ClockNTS = 3579545.0
	sfxFrames   = 60 * 20 // render cap
)

var dacRate = z80ClockPAL / dacCycles // this is the European release

// Script commands used by the PCM voices.
const (
	cmdEnd      = 0x00
	cmdWait     = 0x01 // wait word+1 frames (0 = hold)
	cmdPatch    = 0x02 // FM patch: $5C bytes of register data follow
	cmdLoop     = 0x03 // repeat from event hi(word), arg times (0 = forever)
	cmdGoto     = 0x04
	cmdReturn   = 0x06
	cmdSustain  = 0x12 // wait until the note is released, then continue
	cmdPCMStart = 0x1B // voice arg: start = bank base + word
	cmdPCMLen   = 0x1C // voice arg: length in bytes (1 = silence)
	cmdPCMStep  = 0x1D // voice arg: rate step hi(word), rate = dac * step / 256
	cmdPCMKey   = 0x1E // voice arg: hi(word) != 0 restarts the voice
	cmdPCMBank  = 0x21 // voice arg: bank hi(word) & 31 of the current set
	cmdPCMSet   = 0x25 // set arg: window of the sample list
)

var channelNames = []string{"FM1", "FM2", "FM3", "FM4", "FM5", "FM6 / PCM voice 0", "PSG1", "PSG2", "PSG3", "PSG noise", "PCM voice 1"}

// Commentary: the speech id pushed by the match code (speech_queue_push),
// named after the event that triggers it.
var speechContext = map[int]string{
	0x01: "corner kick", 0x02: "goal kick", 0x03: "throw in", 0x04: "free kick",
	0x05: "penalty kick", 0x06: "offside", 0x08: "half time", 0x09: "rules (match_rules_update)",
	0x0E: "shot or header", 0x13: "match result", 0x14: "match result", 0x20: "rules (match_rules_update)",
	0x21: "keeper rushes out", 0x22: "corner kick (PAL)", 0x23: "goal kick (PAL)", 0x24: "free kick (PAL)",
	0x25: "penalty kick (PAL)", 0x27: "kick-off", 0x29: "card shown", 0x2A: "card shown",
	0x2F: "goal", 0x32: "own goal", 0x42: "time up", 0x44: "goal (lead-in, random)",
}

func musicTable(i int) uint32 { return musicBank + be32(musicBank+uint32(4*i)) }

func scriptAddr(id int) uint32 {
	t0 := musicTable(0)
	return t0 + be32(t0+uint32(4*id))
}

// pcmSampleOffsets returns the distinct sample offsets in the sample list,
// sorted; region i runs to offset i+1 (the last to the end of the bank).
func pcmSampleOffsets() []int {
	seen := map[int]bool{}
	var out []int
	for a := uint32(pcmList); a < pcmListEnd; a += 4 {
		o := int(be32(a))
		if !seen[o] {
			seen[o] = true
			out = append(out, o)
		}
	}
	sort.Ints(out)
	return out
}

func pcmBankBase(set, bank int) int {
	if bank&31 == 0 {
		return 0
	}
	w := pcmSets + be16(pcmSets+uint32(2*set))
	return int(be32(w + uint32(4*((bank&31)-1))))
}

type pcmVoice struct {
	loopPtr, cur int
	loopLen, rem uint16
	step, acc    uint8
}

type pcmEvent struct {
	Frame  int     `json:"frame"`
	Voice  int     `json:"voice"`
	Op     string  `json:"op"` // play, loop (next region when the current one ends), stop
	Sample int     `json:"sample"`
	Start  int     `json:"start"`
	Length int     `json:"length"`
	Rate   float64 `json:"rate_hz"`
}

// scriptRun interprets one script the way the driver does, frame by frame,
// for the commands that matter to PCM.
type scriptRun struct {
	base, p  uint32
	wait     int
	loops    int
	done     bool
	set      int
	bankBase [2]int
	ptr      [2]int
	length   [2]uint16
	step     [2]uint8
	key      [2]bool
	dirty    bool
	keyed    bool
	voice    [2]pcmVoice
	offsets  []int
	events   []pcmEvent
	frame    int
	missing  bool
}

func newScriptRun(id int, offsets []int) *scriptRun {
	a := scriptAddr(id)
	r := &scriptRun{base: a, p: a + 2, offsets: offsets}
	for v := range r.voice {
		r.length[v], r.voice[v].loopLen, r.voice[v].rem = 1, 1, 1
	}
	return r
}

// sampleOf returns the region containing bank offset o and o's position in it.
func sampleOf(offsets []int, o int) (int, int) {
	i := sort.SearchInts(offsets, o+1) - 1
	if i < 0 {
		return -1, o
	}
	return i, o - offsets[i]
}

func regionEnd(offsets []int, i int) int {
	if i+1 < len(offsets) {
		return offsets[i+1]
	}
	return pcmBankEnd - pcmBank
}

// advance processes the events of one frame.
func (r *scriptRun) advance(released bool) {
	for n := 0; n < 256 && !r.done; n++ {
		c, arg, w := rom[r.p], int(rom[r.p+1]), int(be16(r.p+2))
		hi := int(rom[r.p+2])
		v := arg & 1
		switch c {
		case cmdEnd, cmdGoto, cmdReturn:
			r.done = true
			return
		case cmdWait, cmdSustain:
			if c == cmdSustain && released {
				r.wait = 0
				break
			}
			if w == 0 || w >= r.wait {
				r.wait++
				return
			}
			r.wait = 0
		case cmdPatch:
			r.p += 4 + 0x5C
			return
		case cmdLoop:
			if arg == 0 || r.loops != arg {
				if arg != 0 {
					r.loops++
				}
				r.p = r.base + 2 + uint32(4*hi)
				continue
			}
			r.loops = 0
		case cmdPCMSet:
			r.set = arg
		case cmdPCMBank:
			r.bankBase[v] = pcmBankBase(r.set, hi)
		case cmdPCMStart:
			r.ptr[v], r.dirty = r.bankBase[v]+w, true
		case cmdPCMLen:
			r.length[v], r.dirty = uint16(w), true
		case cmdPCMStep:
			r.step[v], r.dirty = uint8(hi), true
		case cmdPCMKey:
			r.key[v], r.dirty = hi != 0, true
		}
		r.p += 4
	}
}

// apply copies the pending PCM settings to the voices (sub_1FE102).
func (r *scriptRun) apply() {
	if !r.dirty {
		return
	}
	for v := range r.voice {
		vc := &r.voice[v]
		changed := vc.loopPtr != r.ptr[v] || vc.loopLen != r.length[v] || vc.step != r.step[v]
		vc.loopPtr, vc.loopLen, vc.step = r.ptr[v], r.length[v], r.step[v]
		op := ""
		switch {
		case r.key[v]:
			vc.cur, vc.rem = vc.loopPtr, vc.loopLen
			op = "play"
			r.keyed = true
		case changed && vc.loopLen <= 1:
			op = "stop"
		case changed:
			op = "loop"
		}
		if op == "" || (op == "stop" && !r.keyed) {
			continue
		}
		e := pcmEvent{Frame: r.frame, Voice: v, Op: op, Sample: -1}
		if op != "stop" {
			s, start := sampleOf(r.offsets, vc.loopPtr)
			e.Sample, e.Start, e.Length = s, start, int(vc.loopLen)
			e.Rate = round1(dacRate * float64(vc.step) / 256)
			if s < 0 || vc.loopPtr+int(vc.loopLen) > regionEnd(r.offsets, s)+64 {
				// A 1-byte placeholder, or a length running far into the
				// following samples: the sample is not in this ROM.
				r.missing = true
			}
		}
		r.events = append(r.events, e)
	}
	r.key = [2]bool{}
	r.dirty = false
}

// mix produces one output byte (sub_1FE146) and reports voice reloads.
func (r *scriptRun) mix(reload func(v int)) byte {
	sum := 0
	for v := range r.voice {
		vc := &r.voice[v]
		if vc.rem != 1 {
			sum += int(int8(rom[pcmBank+vc.cur]))
		}
		old := vc.acc
		vc.acc += vc.step
		if vc.acc < old { // carry
			vc.rem--
			if vc.rem == 0 {
				vc.cur, vc.rem, vc.acc = vc.loopPtr, vc.loopLen, 0
				if reload != nil {
					reload(v)
				}
			} else {
				vc.cur++
			}
		}
	}
	if sum > 127 {
		sum = 127
	} else if sum < -128 {
		sum = -128
	}
	return byte(sum) ^ 0x80 // unsigned 8-bit WAV
}

func (r *scriptRun) idle() bool {
	for _, vc := range r.voice {
		if vc.rem != 1 || vc.loopLen > 1 {
			return false
		}
	}
	return true
}

func round1(f float64) float64 { return float64(int(f*10+0.5)) / 10 }

// render runs the script until it ends and both voices fall silent,
// releasing the note after duration frames. It returns the mixed output
// and, for a sound that keeps looping, the loop in output samples.
func (r *scriptRun) render(duration int, mixOut bool) (out []byte, loopStart, loopEnd int) {
	spf := dacRate / 60 // script frames are counted at 60 Hz
	acc := 0.0
	loopStart, loopEnd = -1, -1
	var reloads []int
	active := 0 // output length when a voice last played
	defer func() {
		if loopEnd < 0 && active < len(out) {
			out = out[:active]
		}
	}()
	for r.frame = 0; r.frame < sfxFrames; r.frame++ {
		if !r.done {
			r.advance(duration > 0 && r.frame >= duration)
		}
		r.apply()
		if !mixOut {
			if r.done {
				break
			}
			continue
		}
		acc += spf
		for ; acc >= 1; acc-- {
			playing := r.voice[0].rem != 1 || r.voice[1].rem != 1
			out = append(out, r.mix(func(v int) {
				if r.done && r.voice[v].loopLen > 1 {
					reloads = append(reloads, len(out)+1)
				}
			}))
			if playing {
				active = len(out)
			}
		}
		if r.done && len(reloads) >= 2 {
			loopStart, loopEnd = reloads[0], reloads[1]
			out = out[:loopEnd]
			break
		}
		if r.done && r.idle() {
			break
		}
	}
	return out, loopStart, loopEnd
}

// writeWAV writes 8-bit unsigned mono PCM, with a smpl loop when loopEnd > 0
// (Godot's importer reads it as the loop points).
func writeWAV(path string, data []byte, rate, loopStart, loopEnd int) {
	var b []byte
	u32 := func(v int) { b = binary.LittleEndian.AppendUint32(b, uint32(v)) }
	u16 := func(v int) { b = binary.LittleEndian.AppendUint16(b, uint16(v)) }
	pad := len(data) & 1
	size := 4 + 8 + 16 + 8 + len(data) + pad
	if loopEnd > 0 {
		size += 8 + 36 + 24
	}
	b = append(b, "RIFF"...)
	u32(size)
	b = append(b, "WAVEfmt "...)
	u32(16)
	u16(1)
	u16(1)
	u32(rate)
	u32(rate)
	u16(1)
	u16(8)
	b = append(b, "data"...)
	u32(len(data))
	b = append(b, data...)
	if pad == 1 {
		b = append(b, 0x80)
	}
	if loopEnd > 0 {
		b = append(b, "smpl"...)
		u32(36 + 24)
		u32(0)
		u32(0)
		u32(1000000000 / rate)
		u32(60)
		u32(0)
		u32(0)
		u32(0)
		u32(1)
		u32(0)
		u32(0)
		u32(0)
		u32(loopStart)
		u32(loopEnd - 1)
		u32(0)
		u32(0)
	}
	must(os.WriteFile(path, b, 0644))
}

func exportSound(dir string) {
	must(os.MkdirAll(filepath.Join(dir, "samples"), 0755))
	must(os.MkdirAll(filepath.Join(dir, "sfx"), 0755))
	offsets := pcmSampleOffsets()

	// Rates the scripts play each sample at (the most common one is used
	// for the raw sample files).
	rates := map[int]map[uint8]int{}
	note := func(r *scriptRun) {
		for _, e := range r.events {
			if e.Sample >= 0 && e.Op == "play" {
				if rates[e.Sample] == nil {
					rates[e.Sample] = map[uint8]int{}
				}
				rates[e.Sample][r.voice[e.Voice].step]++
			}
		}
	}

	type scriptOut struct {
		Script   int        `json:"script"`
		Channel  string     `json:"channel"`
		PCM      []pcmEvent `json:"pcm"`
		Missing  bool       `json:"missing_sample,omitempty"`
		Priority int        `json:"priority"`
	}
	var instruments []scriptOut
	for id := 0; id < 0x300; id++ {
		r := newScriptRun(id, offsets)
		r.render(120, false)
		if len(r.events) == 0 {
			continue
		}
		note(r)
		a := scriptAddr(id)
		instruments = append(instruments, scriptOut{Script: id, Channel: channelName(int(rom[a+3])),
			PCM: r.events, Missing: r.missing, Priority: int(rom[a])})
	}

	type sfxOut struct {
		ID       int        `json:"id"`
		Script   int        `json:"script"`
		Priority int        `json:"priority"`
		Duration int        `json:"duration_frames"`
		Channel  string     `json:"channel"`
		Speech   string     `json:"speech,omitempty"`
		WAV      string     `json:"wav,omitempty"`
		Loop     []int      `json:"loop,omitempty"`
		PCM      []pcmEvent `json:"pcm,omitempty"`
		Missing  bool       `json:"missing_sample,omitempty"`
	}
	var sfx []sfxOut
	t2 := musicTable(2)
	rendered := 0
	for n := 0; n < numSfx; n++ {
		e := t2 + uint32(6*n)
		script := int(be16(e + 4))
		o := sfxOut{ID: n, Script: script, Priority: int(rom[e+1]), Duration: int(be16(e + 2)),
			Speech: speechContext[n]}
		if script < numScripts {
			a := scriptAddr(script)
			o.Channel = channelName(int(rom[a+3]))
			r := newScriptRun(script, offsets)
			out, ls, le := r.render(o.Duration, true)
			if len(r.events) > 0 {
				note(r)
				o.PCM, o.Missing = r.events, r.missing
				if !r.missing && len(out) > 0 {
					p := filepath.Join(dir, "sfx", fmt.Sprintf("sfx_%02X.wav", n))
					writeWAV(p, out, int(dacRate+0.5), ls, le)
					o.WAV = resPath(p)
					if le > 0 {
						o.Loop = []int{ls, le}
					}
					rendered++
				}
			}
		}
		sfx = append(sfx, o)
	}

	type sampleOut struct {
		ID     int     `json:"id"`
		Offset int     `json:"offset"`
		ROM    string  `json:"rom"`
		Length int     `json:"length"`
		Rate   float64 `json:"rate_hz"`
		WAV    string  `json:"wav"`
	}
	var samples []sampleOut
	var missing []int
	for i, o := range offsets {
		n := regionEnd(offsets, i) - o
		if n <= 16 {
			missing = append(missing, i)
			continue
		}
		step, best := uint8(0xFF), 0
		for s, c := range rates[i] {
			if c > best || (c == best && s > step) {
				step, best = s, c
			}
		}
		rate := dacRate * float64(step) / 256
		data := make([]byte, n)
		for k := range data {
			data[k] = rom[pcmBank+o+k] ^ 0x80
		}
		p := filepath.Join(dir, "samples", fmt.Sprintf("pcm_%02d.wav", i))
		writeWAV(p, data, int(rate+0.5), 0, 0)
		samples = append(samples, sampleOut{ID: i, Offset: o, ROM: fmt.Sprintf("$%06X", pcmBank+o), Length: n,
			Rate: round1(rate), WAV: resPath(p)})
	}

	var sets [][]int
	for s := 0; s < numPCMSets; s++ {
		w := pcmSets + be16(pcmSets+uint32(2*s))
		var ids []int
		for b := uint32(0); b < 8 && w+4*b < pcmListEnd; b++ {
			i, _ := sampleOf(offsets, int(be32(w+4*b)))
			ids = append(ids, i)
		}
		sets = append(sets, ids)
	}

	var songs []map[string]any
	for s := 0; s < numSongs; s++ {
		song := decodeSong(musicTable(3 + s))
		song["id"] = s
		song["rom"] = fmt.Sprintf("$%06X", musicTable(3+s))
		songs = append(songs, song)
	}

	writeJSON(filepath.Join(dir, "sound.json"), map[string]any{
		"description": "ISS Deluxe sound: the PCM samples (samples/, signed 8-bit in ROM, written as unsigned WAV) " +
			"and every effect that uses them rendered through a model of the driver's mixer (sfx/). Songs and FM / " +
			"PSG effects are rendered by tools/render_sound.py (runs the driver itself) into rendered/.",
		"driver": map[string]any{
			"dac_rate_hz":  map[string]float64{"pal": round1(z80ClockPAL / dacCycles), "ntsc": round1(z80ClockNTS / dacCycles)},
			"pcm_rate":     "dac_rate * step / 256, step from command $1D; files use the PAL rate",
			"voices":       "2 PCM voices (0: music, e.g. the crowd; 1: commentary), summed with saturation",
			"channels":     channelNames,
			"frame":        "script waits and effect durations count frames (60 Hz here)",
			"speech_queue": "speech_queue_update plays one queued commentary effect every $40 frames (4 queued at most)",
		},
		"samples":         samples,
		"missing_samples": missing,
		"pcm_sets":        sets,
		"sfx":             sfx,
		"instruments":     instruments,
		"songs":           songs,
		"song_format": "song_play / song_order_update / song_pattern_update / song_read_note. A song: 16 track -> " +
			"script words, then a word table of variants; a variant: the pattern table's offset word, the tempo " +
			"(beats a minute, 24 ticks a beat), then the order list of 6-byte entries [delay.w (ticks before the " +
			"entry), pattern, transpose, volume, track] ending in pattern $FF (end) or $FE (jump: the word at +4 is " +
			"the order list offset to continue from); every entry starts its pattern on a free slot (16) playing " +
			"the track's script. A pattern is packed notes: [note | $80 delay is a word | $40 instrument change, " +
			"volume | $80 duration is a word, duration (1-2 bytes, the gate in ticks), delay (1-2 bytes, ticks after " +
			"the previous note), (instrument change: a word, the track's new script)]; note 0 ends the pattern. " +
			"A note queues (volume + the entry's volume, 0-63; pitch = note + 35 + transpose) the track's script, " +
			"whose $0B events play the pitch plus their argument: MIDI note = pitch + 11 + that. The instrument " +
			"scripts' $02 event and the 23 events after it are an FM patch (each [02, 00, register, value] for " +
			"registers $30-$8C), followed by $22 events writing $B0 (feedback / algorithm) and $B4 (stereo, LFO). " +
			"tools/songs_to_midi.py writes the songs as MIDI files from this.",
	})
	fmt.Printf("sound: %d PCM samples (%d missing from this ROM), %d effects rendered, %d PCM instruments\n",
		len(samples), len(missing), rendered, len(instruments))
}

func channelName(c int) string {
	if c < len(channelNames) {
		return channelNames[c]
	}
	return fmt.Sprintf("channel %d", c)
}

// readNote decodes one packed pattern note (song_read_note): note (bit 7
// = an instrument change), volume, duration (the gate), delay, and the
// instrument change's script (or -1), plus the bytes it took.
func readNote(a uint32) ([]int, uint32) {
	b0, b1 := rom[a], rom[a+1]
	p := a + 2
	n := uint32(4)
	dur := int(rom[p])
	if b1&0x80 != 0 {
		dur = int(be16(p))
		p += 2
		n++
	} else {
		p++
	}
	delay := int(rom[p])
	if b0&0x80 != 0 {
		delay = int(be16(p))
		p++
		n++
	}
	note := int(b0 & 0x7F)
	cmd := -1
	if note&0x40 != 0 {
		note = (note & 0x3F) | 0x80
		cmd = int(be16(p + 1))
		n += 2
	}
	return []int{note, int(b1 & 0x3F), dur, delay, cmd}, n
}

// trackInstrument says how script id plays a queued note: the pitch
// offset its $0B event adds (following a $04 goto), a fixed pitch ($0A,
// percussion), or a drum map ($14 / $16 entries picking a script by
// pitch, script_start_1).
func trackInstrument(id int) map[string]any {
	out := map[string]any{"script": id}
	if id == 0 {
		return out
	}
	for hop := 0; hop < 4; hop++ {
		a := scriptAddr(id) + 2
		if c := rom[a]; c == 0x14 || c == 0x16 {
			var drums [][]int
			for rom[a] == 0x14 || rom[a] == 0x16 {
				drums = append(drums, []int{int(rom[a+1]), int(be16(a + 2))})
				a += 4
			}
			out["drums"] = drums
			return out
		}
		for k := 0; k < 64; k++ {
			c, arg := rom[a], rom[a+1]
			switch c {
			case 0:
				return out
			case 2:
				a += 0x5C
			case 4:
				id = int(be16(a + 2))
				k = 64
				continue
			case 0x0A:
				out["fixed_pitch"] = int(arg)
				return out
			case 0x0B:
				out["pitch_offset"] = int(int8(arg))
				return out
			}
			a += 4
		}
	}
	return out
}

// decodeSong reads a song's tracks, variants, order lists and patterns
// (see song_format in sound.json).
func decodeSong(s uint32) map[string]any {
	tracks := make([]int, 16)
	var instruments []map[string]any
	for i := range tracks {
		tracks[i] = int(be16(s + uint32(2*i)))
		instruments = append(instruments, trackInstrument(tracks[i]))
	}
	vt := s + 32
	nvar := int(be16(vt)) / 2
	var variants []map[string]any
	for v := 0; v < nvar; v++ {
		va := vt + uint32(be16(vt+uint32(2*v)))
		pt := va + uint32(be16(va))
		o := va + 4
		var order []map[string]any
		used := map[int]bool{}
		for n := 0; n < 4096; n++ {
			delay := int(be16(o))
			pat := int(rom[o+2])
			if pat == 0xFF {
				order = append(order, map[string]any{"delay": delay, "end": true})
				break
			}
			if pat == 0xFE {
				order = append(order, map[string]any{"delay": delay, "jump": int(be16(o+4)) / 6})
				break
			}
			order = append(order, map[string]any{"delay": delay, "pattern": pat, "transpose": int(int8(rom[o+3])),
				"volume": int(int8(rom[o+4])), "track": int(rom[o+5])})
			used[pat] = true
			o += 6
		}
		npat := 0
		for p := range used {
			if p+1 > npat {
				npat = p + 1
			}
		}
		patterns := make([][][]int, npat)
		for p := 0; p < npat; p++ {
			if !used[p] {
				continue
			}
			a := pt + uint32(be16(pt+uint32(2*p)))
			for k := 0; k < 4096; k++ {
				nt, n := readNote(a)
				patterns[p] = append(patterns[p], nt)
				a += n
				if nt[0] == 0 {
					break
				}
			}
		}
		variants = append(variants, map[string]any{"tempo": int(be16(va + 2)), "order": order, "patterns": patterns})
	}
	return map[string]any{"track_scripts": tracks, "track_instruments": instruments, "variants": variants}
}
