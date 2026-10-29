class_name PixelPalette
extends RefCounted
## The limited palette of the pixel pass (ui/pixel_art.gdshader, `use_palette`), and the lookup volume built from it.
## The shader used to measure the distance to every palette colour for every screen pixel; instead this builds, ONCE, two
## 32^3 3D textures indexed by the pixel's colour: `a` = the nearest palette colour (rgb) and how far from it the pixel is
## towards the second nearest (alpha), `b` = the second nearest colour. A pixel then costs two texture reads.

const PALETTE: Array[Color] = [
	Color(0.0314, 0.0314, 0.0471),
	Color(0.1255, 0.1176, 0.1569),
	Color(0.2510, 0.2353, 0.2902),
	Color(0.4078, 0.3922, 0.4549),
	Color(0.5804, 0.5647, 0.6196),
	Color(0.7686, 0.7529, 0.8000),
	Color(0.9255, 0.9176, 0.9412),
	Color(0.1725, 0.1020, 0.0941),
	Color(0.3059, 0.1725, 0.1333),
	Color(0.4784, 0.2902, 0.1882),
	Color(0.6588, 0.4235, 0.2588),
	Color(0.8314, 0.5961, 0.3765),
	Color(0.1412, 0.1098, 0.2510),
	Color(0.2353, 0.1882, 0.4078),
	Color(0.3608, 0.2980, 0.5490),
	Color(0.1569, 0.2510, 0.5020),
	Color(0.3137, 0.4706, 0.7843),
	Color(0.1176, 0.2353, 0.1333),
	Color(0.2353, 0.4235, 0.2196),
	Color(0.4078, 0.6275, 0.3294),
	Color(0.6275, 0.7843, 0.4706),
	Color(0.3137, 0.0784, 0.1098),
	Color(0.5490, 0.1412, 0.1569),
	Color(0.7843, 0.2353, 0.2196),
	Color(0.9255, 0.4706, 0.3922),
	Color(0.5882, 0.3922, 0.3137),
	Color(0.8392, 0.6118, 0.4706),
	Color(0.9569, 0.7843, 0.6275),
	Color(0.7843, 0.6275, 0.2353),
	Color(0.9647, 0.8392, 0.3922),
	Color(0.1569, 0.3922, 0.4314),
	Color(1.0000, 1.0000, 1.0000)]
const SIZE := 32


## Returns [lut_a, lut_b] (ImageTexture3D, nearest filtering is set in the shader).
static func build_lut() -> Array:
	var layers_a: Array[Image] = []
	var layers_b: Array[Image] = []
	for bz in SIZE:
		var ia := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var ib := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for gy in SIZE:
			for rx in SIZE:
				var c := Vector3(rx, gy, bz) / float(SIZE - 1)
				var d1 := 1e9
				var d2 := 1e9
				var c1 := Color.BLACK
				var c2 := Color.BLACK
				for p in PALETTE:
					var dv := (c - Vector3(p.r, p.g, p.b)) * Vector3(0.9, 1.2, 0.7)     # green matters most to the eye, blue least
					var d := dv.length_squared()
					if d < d1:
						d2 = d1
						c2 = c1
						d1 = d
						c1 = p
					elif d < d2:
						d2 = d
						c2 = p
				var mixv := sqrt(d1) / maxf(sqrt(d1) + sqrt(d2), 0.0001)
				ia.set_pixel(rx, gy, Color(c1.r, c1.g, c1.b, mixv))
				ib.set_pixel(rx, gy, Color(c2.r, c2.g, c2.b, 1.0))
		layers_a.append(ia)
		layers_b.append(ib)
	var ta := ImageTexture3D.new()
	ta.create(Image.FORMAT_RGBA8, SIZE, SIZE, SIZE, false, layers_a)
	var tb := ImageTexture3D.new()
	tb.create(Image.FORMAT_RGBA8, SIZE, SIZE, SIZE, false, layers_b)
	return [ta, tb]
