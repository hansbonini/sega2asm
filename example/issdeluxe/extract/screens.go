package main

import (
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"

	"sega2asm/types"
)

// Front-end screens (loader at $01EB38, screen number in $FF175C): a backdrop
// group (23; 26 for screens $34-$38; 24 from $3A; 25 for $39) provides tiles
// at the base VRAM tile, its map on plane A and palette lines 2-3; the screen's
// own group (27 + screen) adds its tiles right after the backdrop's, its map
// (numbered from the same base, priority set) as the text nametable the menu
// text is drawn into, and palette lines 0-1.
const (
	grpScreen0   = 27
	numScreens   = 59
	grpBackdrop  = 23
	screenWidth  = 32 // visible cells (H32)
	screenHeight = 28
)

func backdropGroup(id int) int {
	switch {
	case id == 0x39:
		return 25
	case id >= 0x3A:
		return 24
	case id >= 0x34 && id <= 0x38:
		return 26
	}
	return grpBackdrop
}

// groupEntries returns the number of entries of group g.
func groupEntries(g int) int {
	ga := group(g)
	if be16(ga) == 0 {
		return int(be32(ga)) / 4
	}
	return int(be16(ga)) / 2
}

func cramLines(b []byte) []color.RGBA {
	var out []color.RGBA
	for i := 0; i+1 < len(b); i += 2 {
		out = append(out, types.MDColor(uint16(b[i])<<8|uint16(b[i+1])))
	}
	return out
}

// drawScreenPlane draws the visible part of a 64-cell-wide map (tile numbers
// relative to tiles) with a 64-colour palette; only non-zero pixels of cells
// whose priority bit equals prio are drawn.
func drawScreenPlane(img *image.RGBA, m, tiles []byte, pal []color.RGBA, prio bool) {
	for row := 0; row < screenHeight; row++ {
		for col := 0; col < screenWidth; col++ {
			o := 2 * (row*64 + col)
			if o+1 >= len(m) {
				continue
			}
			w := be16s(m, o)
			if (w&0x8000 != 0) != prio {
				continue
			}
			t := int(w & 0x7FF)
			if t*32+32 > len(tiles) {
				continue
			}
			line := int(w>>13) & 3
			for y := 0; y < 8; y++ {
				for x := 0; x < 8; x++ {
					v := tiles[t*32+y*4+x/2]
					if x&1 == 0 {
						v >>= 4
					}
					v &= 15
					if v == 0 || line*16+int(v) >= len(pal) {
						continue
					}
					px, py := x, y
					if w&0x800 != 0 {
						px = 7 - x
					}
					if w&0x1000 != 0 {
						py = 7 - y
					}
					img.SetRGBA(col*8+px, row*8+py, pal[line*16+int(v)])
				}
			}
		}
	}
}

func exportScreens(dir string) {
	must(os.MkdirAll(dir, 0755))
	type screenOut struct {
		Screen   int    `json:"screen"`
		Group    int    `json:"group"`
		Backdrop int    `json:"backdrop_group"`
		PNG      string `json:"png"`
	}
	var all []screenOut
	for id := 0; id < numScreens; id++ {
		g := grpScreen0 + id
		if groupEntries(g) < 3 || be16(entry(g, 0)) == 0xFFFF {
			continue // empty slot
		}
		b := backdropGroup(id)
		btiles := unpack(entry(b, 0))
		bmap := unpack(entry(b, 1))
		bpal := unpack(entry(b, 2))
		stiles := unpack(entry(g, 0))
		smap := unpack(entry(g, 1))
		spal := unpack(entry(g, 2))
		tiles := append(append([]byte(nil), btiles...), stiles...)
		pal := make([]color.RGBA, 64)
		copy(pal[0:], cramLines(spal))
		copy(pal[32:], cramLines(bpal))
		img := image.NewRGBA(image.Rect(0, 0, screenWidth*8, screenHeight*8))
		for i := range img.Pix {
			img.Pix[i] = 0
		}
		// Backdrop colour, then plane A (backdrop, low priority), plane B
		// (screen, priority toggled by the loader) and any high-priority
		// backdrop cells on top.
		bg := pal[0]
		for y := 0; y < img.Bounds().Dy(); y++ {
			for x := 0; x < img.Bounds().Dx(); x++ {
				img.SetRGBA(x, y, color.RGBA{bg.R, bg.G, bg.B, 255})
			}
		}
		sm := append([]byte(nil), smap...)
		for i := 0; i+1 < len(sm); i += 2 {
			sm[i] ^= 0x80 // the loader toggles the priority bit
		}
		drawScreenPlane(img, bmap, tiles, pal, false)
		drawScreenPlane(img, sm, tiles, pal, false)
		drawScreenPlane(img, bmap, tiles, pal, true)
		drawScreenPlane(img, sm, tiles, pal, true)
		p := filepath.Join(dir, fmt.Sprintf("screen_%02X.png", id))
		must(types.WritePNG(p, img))
		all = append(all, screenOut{Screen: id, Group: g, Backdrop: b, PNG: resPath(p)})
	}
	writeJSON(filepath.Join(dir, "screens.json"), map[string]any{
		"description": "Front-end screens as loaded by $01EB38 for screen number $FF175C: backdrop group (plane A) " +
			"under the screen's own group (the text nametable the menus draw into). Renders without the menu text, " +
			"cursors and sprites that the front-end objects add at run time.",
		"screens": all,
	})
	fmt.Printf("screens: %d front-end screens\n", len(all))
	exportFonts(dir)
}

// exportFonts renders the front-end fonts of text_draw_large ($01F29E: 8x16,
// tiles $90 + c - '-' over $E0 + c - '-') and text_draw_small ($01F358: 8x8,
// tiles $130 + c - '-') from the backdrop group's tiles, in palette line 2
// (normal) and line 3 (rect_highlight sets the palette bit).
func exportFonts(dir string) {
	btiles := unpack(entry(grpBackdrop, 0))
	pal := make([]color.RGBA, 64)
	copy(pal[32:], cramLines(unpack(entry(grpBackdrop, 2))))
	const first, count = 0x2D, 0x50
	glyph := func(img *image.RGBA, t, ox, oy, line int) {
		if t*32+32 > len(btiles) {
			return
		}
		for y := 0; y < 8; y++ {
			for x := 0; x < 8; x++ {
				v := btiles[t*32+y*4+x/2]
				if x&1 == 0 {
					v >>= 4
				}
				v &= 15
				if v != 0 {
					img.SetRGBA(ox+x, oy+y, pal[line*16+int(v)])
				}
			}
		}
	}
	for _, f := range []struct {
		name   string
		base   int
		height int
	}{{"font_large", 0x90, 16}, {"font_small", 0x130, 8}} {
		for _, line := range []int{2, 3} {
			img := image.NewRGBA(image.Rect(0, 0, count*8, f.height))
			for i := 0; i < count; i++ {
				glyph(img, f.base+i, i*8, 0, line)
				if f.height == 16 {
					glyph(img, f.base+0x50+i, i*8, 8, line)
				}
			}
			suffix := ""
			if line == 3 {
				suffix = "_hi"
			}
			must(types.WritePNG(filepath.Join(dir, f.name+suffix+".png"), img))
		}
	}
	writeJSON(filepath.Join(dir, "fonts.json"), map[string]any{
		"description": "Front-end fonts (text_draw_large 8x16, text_draw_small 8x8): glyph i is character '-' + i " +
			"(ASCII $2D-$7C, '@' is the space); *_hi.png is the highlighted colour (palette line 3).",
		"first_char": first,
		"count":      count,
		"large":      map[string]any{"png": "res://assets/iss/screens/font_large.png", "hi": "res://assets/iss/screens/font_large_hi.png", "size": []int{8, 16}},
		"small":      map[string]any{"png": "res://assets/iss/screens/font_small.png", "hi": "res://assets/iss/screens/font_small_hi.png", "size": []int{8, 8}},
	})
}
