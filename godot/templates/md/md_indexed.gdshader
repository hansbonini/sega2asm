shader_type canvas_item;
// Draw an index texture through a palette texture (16 x N, one row per
// 16-colour palette line, e.g. *.pal.png).
//
// Index textures store CRAM indices: 0-15 for single-line graphics (*.idx.png,
// the line is chosen with `palette_line`), or line*16 + colour for sprites
// whose pieces use several lines (0-63). Colour 0 of every line is
// transparent. Swapping the palette texture reproduces Mega Drive palette
// tricks such as team kits and fades without touching the graphics.
//
// shadow_highlight emulates the VDP's shadow/highlight mode (register 12
// bit 3) for sprites: line 3 colour 15 is not drawn but halves the colour
// underneath (shadow), line 3 colour 14 brightens it (highlight). Both are
// drawn as 50% black / white, which is the same blend.

uniform sampler2D palette : filter_nearest;
uniform int palette_line = 0;
uniform bool index0_transparent = true;
uniform bool shadow_highlight = false;

void fragment() {
	int idx = int(round(texture(TEXTURE, UV).r * 255.0));
	if (index0_transparent && (idx & 15) == 0) {
		discard;
	}
	int line = palette_line + (idx >> 4);
	if (shadow_highlight && line == 3 && (idx & 15) >= 14) {
		COLOR = (idx & 15) == 15 ? vec4(0.0, 0.0, 0.0, 0.5) : vec4(1.0, 1.0, 1.0, 0.5);
	} else {
		COLOR = texelFetch(palette, ivec2(idx & 15, line), 0);
	}
}
