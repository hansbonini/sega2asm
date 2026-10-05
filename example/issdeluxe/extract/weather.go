package main

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"

	"sega2asm/types"
)

// Weather overlay: during a match plane A holds res16 entry g_weather, a
// 64x32-cell map scrolled together with the pitch (plane B), over the
// overlay/HUD tiles of res16 entry 5. Snow and rain only use tiles
// $103-$106, two 2-tile slots that the VBlank code at $01B412 rewrites from
// res04 entries 7 (snow) and 8 (rain); fine weather has an empty map.
const (
	grpOverlay       = 16    // res16: plane A maps (entries 0-2 by g_weather), window map (3), tiles (5)
	entOverlayTiles  = 5     //
	overlaySlotA     = 0x103 // tile slots rewritten by the weather animation
	overlaySlotB     = 0x105
	overlayCols      = 64
	overlayRows      = 32
	entSnowFrames    = 7 // res04: 16 x 2 tiles, raw
	entRainFrames    = 8 // res04: 8 x 2 tiles, raw
	weatherAnimTicks = 256
)

type weatherOut struct {
	Weather    int      `json:"g_weather"`
	Name       string   `json:"name"`
	Frames     []string `json:"frames"`
	FrameTicks int      `json:"frame_ticks"` // 60 Hz frames per animation frame
}

// weatherStates simulates the tile uploads of $01B412 for weather w over one
// period and returns the (slot A, slot B) chunk indices after each upload
// together with the number of frames each state is shown.
func weatherStates(w int) (states [][2]int, ticks int) {
	if w != 0 && w != 2 {
		return nil, 0 // fine: no animation, no overlay
	}
	var a, b int
	step := func(f int) bool {
		switch w {
		case 0: // snow: every 8 frames, alternating slots
			if f&7 != 0 {
				return false
			}
			if f&8 == 0 {
				a = (f >> 4) & 15
			} else {
				b = ((f + 0x80) >> 4) & 15
			}
		case 2: // rain: every frame, alternating slots
			if f&1 == 0 {
				a = (f >> 1) & 7
			} else {
				b = ((f + 8) >> 1) & 7
			}
		default:
			return false
		}
		return true
	}
	// Run one period to settle both slots, record the second.
	for f := 0; f < weatherAnimTicks; f++ {
		step(f)
	}
	for f := 0; f < weatherAnimTicks; f++ {
		if step(f) {
			states = append(states, [2]int{a, b})
		}
	}
	if w == 0 {
		return states, 8
	}
	// Rain repeats every 16 frames.
	return states[:16], 1
}

// exportWeather renders the plane A weather overlay per animation state as
// CRAM-index images (line 3 = the stadium palette).
func exportWeather(dir string) {
	must(os.MkdirAll(dir, 0755))
	tiles := unpack(entry(grpOverlay, entOverlayTiles))
	var all []weatherOut
	for w, name := range weatherNames {
		m := unpack(entry(grpOverlay, w))
		wo := weatherOut{Weather: w, Name: name, Frames: []string{}}
		states, ticks := weatherStates(w)
		wo.FrameTicks = ticks
		var src []byte
		switch w {
		case 0:
			src = rom[entry(grpMisc, entSnowFrames):]
		case 2:
			src = rom[entry(grpMisc, entRainFrames):]
		}
		for i, st := range states {
			t := append([]byte(nil), tiles...)
			copy(t[overlaySlotA*32:], src[st[0]*64:st[0]*64+64])
			copy(t[overlaySlotB*32:], src[st[1]*64:st[1]*64+64])
			p := filepath.Join(dir, fmt.Sprintf("%s_%02d.png", name, i))
			must(types.WritePNG(p, renderPlane(m, t, overlayCols, overlayRows)))
			wo.Frames = append(wo.Frames, resPath(p))
		}
		all = append(all, wo)
	}
	writeJSON(filepath.Join(dir, "weather.json"), map[string]any{
		"description": "Weather overlay on plane A: a 512x256 CRAM-index image per animation state (palette line 3, " +
			"colour 0 transparent), tiled over the stadium map from its origin (plane A scrolls with the pitch). " +
			"Advance one frame every frame_ticks 60 Hz frames. Fine weather has no overlay.",
		"weathers": all,
	})
	fmt.Printf("weather: snow %d frames, rain %d frames\n", len(all[0].Frames), len(all[2].Frames))
}

// renderPlane draws a cols x rows nametable (big-endian words) as a
// CRAM-index image.
func renderPlane(m, tiles []byte, cols, rows int) *image.Gray {
	img := image.NewGray(image.Rect(0, 0, cols*8, rows*8))
	for c := 0; c < cols*rows && 2*c+1 < len(m); c++ {
		w := be16s(m, 2*c)
		t := int(w & 0x7FF)
		if t*32+32 > len(tiles) {
			continue
		}
		line := int(w>>13) & 3
		hf, vf := w&0x800 != 0, w&0x1000 != 0
		for y := 0; y < 8; y++ {
			for x := 0; x < 8; x++ {
				v := tiles[t*32+y*4+x/2]
				if x&1 == 0 {
					v >>= 4
				}
				v &= 15
				if v == 0 {
					continue
				}
				px, py := x, y
				if hf {
					px = 7 - x
				}
				if vf {
					py = 7 - y
				}
				img.SetGray((c%cols)*8+px, (c/cols)*8+py, color.Gray{Y: uint8(line*16) + v})
			}
		}
	}
	return img
}
