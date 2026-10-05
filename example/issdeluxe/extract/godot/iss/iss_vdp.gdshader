shader_type canvas_item;
// The Mega Drive VDP's picture for the front end, computed per pixel from
// the same state the hardware has: 64 KB of VRAM (tiles and the plane
// nametables), the CRAM colours and the sprite table. Planes B and A
// (64 x 32 cells, full-screen scroll or, register 11's cell and line
// modes, each line its own horizontal scroll), 64 sprites in link order, the
// priority rules and shadow/highlight mode (register 12 bit 3): planes are
// shadowed unless one of them has priority at the pixel, and sprite colours
// 62 / 63 brighten / darken what is under them instead of being drawn.

uniform sampler2D vram : filter_nearest;   // R8, 256 x 256: byte a at (a & 255, a >> 8)
uniform sampler2D cram : filter_nearest;   // RGBA8, 64 x 1
uniform sampler2D sat : filter_nearest;    // R8, 512 x 1: 64 sprites x 8 bytes
uniform int plane_a = 8192;
uniform int plane_b = 0;
uniform int plane_w = 4096;
uniform int plane_cols = 64;
uniform int plane_rows = 32;
uniform bool vline_scroll = false;
uniform int vlines_a[224];
uniform int vlines_b[224];
uniform bool display = true;
uniform int window_h = 0;
uniform int window_v = 0;
uniform int scroll_ax = 0;
uniform int scroll_ay = 0;
uniform int scroll_bx = 0;
uniform int scroll_by = 0;
uniform bool line_scroll = false;
uniform int lines_a[224];
uniform int lines_b[224];
uniform int sprites = 0;
uniform int backdrop = 32;
uniform bool shadow_highlight = true;
uniform bool show_a = true;
uniform bool show_b = true;
// Only the pixels a plane or sprite with priority gives (the rest
// transparent): drawn above figures that stand for low-priority sprites.
uniform bool high_only = false;

int vb(int a) {
	a = a & 65535;
	return int(round(texelFetch(vram, ivec2(a & 255, a >> 8), 0).r * 255.0));
}

int vw(int a) {
	return (vb(a) << 8) | vb(a + 1);
}

int tile_px(int tile, int x, int y) {
	int b = vb(tile * 32 + y * 4 + (x >> 1));
	return (x & 1) == 0 ? (b >> 4) : (b & 15);
}

int sb(int i) {
	return int(round(texelFetch(sat, ivec2(i, 0), 0).r * 255.0));
}

// Colour index (0 = transparent) | priority << 8.
int plane_px(int base, int x, int y) {
	int e = vw(base + 2 * (((y >> 3) & (plane_rows - 1)) * plane_cols + ((x >> 3) & (plane_cols - 1))));
	int px = x & 7;
	int py = y & 7;
	if ((e & 2048) != 0) { px = 7 - px; }
	if ((e & 4096) != 0) { py = 7 - py; }
	int v = tile_px(e & 2047, px, py);
	int c = v == 0 ? 0 : ((e >> 13) & 3) * 16 + v;
	return c | (((e >> 15) & 1) << 8);
}

// The window plane (32 cells wide in H32), unscrolled.
int window_px(int x, int y) {
	int e = vw(plane_w + 2 * (((y >> 3) & 31) * 32 + ((x >> 3) & 31)));
	int px = x & 7;
	int py = y & 7;
	if ((e & 2048) != 0) { px = 7 - px; }
	if ((e & 4096) != 0) { py = 7 - py; }
	int v = tile_px(e & 2047, px, py);
	int c = v == 0 ? 0 : ((e >> 13) & 3) * 16 + v;
	return c | (((e >> 15) & 1) << 8);
}

bool in_window(int x, int y) {
	if (window_h == 0 && window_v == 0) { return false; }
	int wx = (window_h & 31) * 16;
	int wy = (window_v & 31) * 8;
	bool h = (window_h & 128) != 0 ? x >= wx : x < wx;
	bool v = (window_v & 128) != 0 ? y >= wy : y < wy;
	return h || v;
}

int sprite_px(int x, int y) {
	for (int i = 0; i < 64; i++) {
		if (i >= sprites) { break; }
		int o = i * 8;
		int sy = (((sb(o) << 8) | sb(o + 1)) & 1023) - 128;
		int size = sb(o + 2);
		int e = (sb(o + 4) << 8) | sb(o + 5);
		int sx = (((sb(o + 6) << 8) | sb(o + 7)) & 511) - 128;
		int sw = ((size >> 2) & 3) + 1;
		int sh = (size & 3) + 1;
		int tx = x - sx;
		int ty = y - sy;
		if (tx < 0 || ty < 0 || tx >= sw * 8 || ty >= sh * 8) { continue; }
		int px = (e & 2048) != 0 ? sw * 8 - 1 - tx : tx;
		int py = (e & 4096) != 0 ? sh * 8 - 1 - ty : ty;
		int v = tile_px((e & 2047) + (px >> 3) * sh + (py >> 3), px & 7, py & 7);
		if (v != 0) {
			return ((e >> 13) & 3) * 16 + v | (((e >> 15) & 1) << 8);
		}
	}
	return 0;
}

vec3 colour(int c) {
	return texelFetch(cram, ivec2(c & 63, 0), 0).rgb;
}

void fragment() {
	int x = int(floor(UV.x * 256.0));
	int y = int(floor(UV.y * 224.0));
	int bx = line_scroll ? lines_b[y] : scroll_bx;
	int ax = line_scroll ? lines_a[y] : scroll_ax;
	int by = vline_scroll ? vlines_b[y] : scroll_by;
	int ay = vline_scroll ? vlines_a[y] : scroll_ay;
	int b = show_b ? plane_px(plane_b, x - bx, y + by) : 0;
	int a = show_a ? (in_window(x, y) ? window_px(x, y) : plane_px(plane_a, x - ax, y + ay)) : 0;
	int s = sprite_px(x, y);
	int bc = b & 255; bool bp = (b & 256) != 0;
	int ac = a & 255; bool ap = (a & 256) != 0;
	int sc = s & 255; bool sp = (s & 256) != 0;
	int c = 0;
	bool hi = false;
	vec3 rgb;
	if (!shadow_highlight) {
		if (bc != 0 && !bp) { c = bc; }
		if (ac != 0 && !ap) { c = ac; }
		if (sc != 0 && !sp) { c = sc; }
		if (bc != 0 && bp) { c = bc; hi = true; }
		if (ac != 0 && ap) { c = ac; hi = true; }
		if (sc != 0 && sp) { c = sc; hi = true; }
		rgb = colour(c != 0 ? c : backdrop);
	} else {
		if (bc != 0 && !bp) { c = bc; }
		if (ac != 0 && !ap) { c = ac; }
		if (bc != 0 && bp) { c = bc; hi = true; }
		if (ac != 0 && ap) { c = ac; hi = true; }
		int shade = (bp || ap) ? 1 : 0;
		if (sc == 62) {
			shade = min(2, shade + 1);
		} else if (sc == 63) {
			shade = 0;
		} else if (sc != 0 && (sp || !((bc != 0 && bp) || (ac != 0 && ap)))) {
			c = sc;
			hi = sp;
			if (sp || (c & 15) == 14) { shade = 1; }
		}
		rgb = colour(c != 0 ? c : backdrop);
		if (shade == 0) {
			rgb = rgb * 0.5;
		} else if (shade == 2) {
			rgb = rgb * 0.5 + vec3(0.5);
		}
	}
	if (high_only && !hi) {
		discard;
	}
	if (!display) {
		rgb = vec3(0.0);
	}
	COLOR = vec4(rgb, 1.0);
}
