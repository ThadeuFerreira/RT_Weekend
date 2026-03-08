// =============================================================
// texture_image.odin — Image texture loaded via vendor:stb/image
// =============================================================
//
// Texture_Image holds either 8-bit (bdata) or float (fdata) pixel data
// loaded from disk. Use texture_image_load for LDR (bdata) or
// texture_image_loadf for HDR (fdata); convert_to_bytes fills bdata
// from fdata for GPU upload or clamped pixel access.
//
// Cleanup: call texture_image_destroy(img) or use defer so stb-allocated
// and locally allocated buffers are freed.
//
// Compute shaders: use texture_image_byte_slice to get contiguous
// RGB data for SSBO upload, or texture_image_float_slice for float
// texels; layout is row-major, bytes_per_pixel = 3.
//

package raytrace

import "core:mem"
import "core:strings"
import stbi "vendor:stb/image"

Texture_Image :: struct {
	bytes_per_pixel:    int, // 3 for RGB
	image_width:        int,
	image_height:       int,
	bytes_per_scanline: int,

	fdata: [^]f32, // linear float data (RGBRGB...), owned by stb or nil
	bdata: [^]u8,  // linear 8-bit data (RGBRGB...), stb-owned or our alloc
	// When bdata is allocated in convert_to_bytes we own it (mem.alloc);
	// when from load() stb owns it (image_free). texture_image_destroy
	// uses fdata_owned / bdata_owned to decide which free to use.
	fdata_owned: bool, // true => fdata from stb (image_free)
	bdata_owned: bool, // true => we allocated bdata (mem.free); false => from stb (image_free)
}

// _clamp_pixel clamps x to [low, high-1] for use as pixel index.
// Named to avoid shadowing math.clamp / interval_clamp elsewhere in the package.
@(private)
_clamp_pixel :: proc(x, low, high: int) -> int {
	if high <= low do return low
	if x < low do return low
	if x >= high do return high - 1
	return x
}

float_to_byte :: proc(value: f32) -> u8 {
	if value <= 0.0 do return 0
	if value >= 1.0 do return 255
	return u8(256.0 * value)
}

texture_image_init :: proc() -> Texture_Image {
	return Texture_Image{
		bytes_per_pixel = 3,
		image_width     = 0,
		image_height    = 0,
		bytes_per_scanline = 0,
		fdata = nil,
		bdata = nil,
		fdata_owned = false,
		bdata_owned = false,
	}
}

texture_image_destroy :: proc(img: ^Texture_Image) {
	if img == nil do return
	if img.fdata != nil && img.fdata_owned {
		stbi.image_free(img.fdata)
		img.fdata = nil
		img.fdata_owned = false
	}
	if img.bdata != nil {
		if img.bdata_owned {
			mem.free(img.bdata)
		} else {
			stbi.image_free(img.bdata)
		}
		img.bdata = nil
		img.bdata_owned = false
	}
	img.image_width = 0
	img.image_height = 0
	img.bytes_per_scanline = 0
}

// texture_image_load loads an LDR image from disk into bdata (u8).
// Returns false on failure and leaves img in a safe empty state.
texture_image_load :: proc(img: ^Texture_Image, filename: string) -> bool {
	if img == nil do return false
	texture_image_destroy(img)

	cname := strings.clone_to_cstring(filename)
	defer delete(cname)

	x, y, comp: i32
	desired_channels: i32 = 3
	data := stbi.load(cname, &x, &y, &comp, desired_channels)
	if data == nil do return false

	img.image_width = int(x)
	img.image_height = int(y)
	img.bytes_per_pixel = 3
	img.bytes_per_scanline = img.image_width * img.bytes_per_pixel
	img.bdata = data
	img.bdata_owned = false // stb owns it → image_free in destroy
	img.fdata = nil
	img.fdata_owned = false
	return true
}

// texture_image_loadf loads an HDR/float image from disk into fdata (f32).
// Returns false on failure. Call texture_image_convert_to_bytes to fill
// bdata for pixel_data or GPU upload.
texture_image_loadf :: proc(img: ^Texture_Image, filename: string) -> bool {
	if img == nil do return false
	texture_image_destroy(img)

	cname := strings.clone_to_cstring(filename)
	defer delete(cname)

	x, y, comp: i32
	desired_channels: i32 = 3
	data := stbi.loadf(cname, &x, &y, &comp, desired_channels)
	if data == nil do return false

	img.image_width = int(x)
	img.image_height = int(y)
	img.bytes_per_pixel = 3
	img.bytes_per_scanline = img.image_width * img.bytes_per_pixel
	img.fdata = data
	img.fdata_owned = true // stb owns it → image_free in destroy
	img.bdata = nil
	img.bdata_owned = false
	return true
}

texture_image_width :: proc(img: ^Texture_Image) -> int {
	if img == nil do return 0
	if img.fdata == nil && img.bdata == nil do return 0
	return img.image_width
}

texture_image_height :: proc(img: ^Texture_Image) -> int {
	if img == nil do return 0
	if img.fdata == nil && img.bdata == nil do return 0
	return img.image_height
}

// texture_image_convert_to_bytes converts fdata to bdata using float_to_byte.
// No-op if fdata is nil. Leaves fdata intact. Allocates bdata with mem.alloc
// (freed in texture_image_destroy).
texture_image_convert_to_bytes :: proc(img: ^Texture_Image) {
	if img == nil || img.fdata == nil do return
	// If we already have bdata we own, replace it (e.g. reloaded fdata)
	if img.bdata != nil && img.bdata_owned {
		mem.free(img.bdata)
		img.bdata = nil
	}
	if img.bdata != nil && !img.bdata_owned {
		stbi.image_free(img.bdata)
		img.bdata = nil
	}

	size := img.image_width * img.image_height * img.bytes_per_pixel
	ptr, alloc_err := mem.alloc(size)
	if alloc_err != nil {
		return
	}
	img.bdata = ([^]u8)(ptr)
	img.bdata_owned = true

	num_channels := size
	for i in 0 ..< num_channels {
		img.bdata[i] = float_to_byte(img.fdata[i])
	}
}

// texture_image_pixel_data returns a pointer to the RGB byte at (x, y).
// Coordinates are clamped to image bounds. If only fdata is present,
// convert_to_bytes is called first. Returns nil if no image is loaded.
texture_image_pixel_data :: proc(img: ^Texture_Image, x, y: int) -> ^u8 {
	if img == nil do return nil
	if img.fdata == nil && img.bdata == nil do return nil
	if img.bdata == nil && img.fdata != nil {
		texture_image_convert_to_bytes(img)
	}
	if img.bdata == nil do return nil

	px := _clamp_pixel(x, 0, img.image_width)
	py := _clamp_pixel(y, 0, img.image_height)
	offset := py * img.bytes_per_scanline + px * img.bytes_per_pixel
	return &img.bdata[offset]
}

// texture_image_byte_slice returns a slice over the contiguous RGB byte
// data for GPU upload (e.g. SSBO or texture). Length is
// width * height * bytes_per_pixel. If only fdata is present,
// convert_to_bytes is called first. Returns an empty slice if no image.
// The slice is valid until texture_image_destroy or the next load.
texture_image_byte_slice :: proc(img: ^Texture_Image) -> []u8 {
	if img == nil do return nil
	if img.fdata == nil && img.bdata == nil do return nil
	if img.bdata == nil && img.fdata != nil {
		texture_image_convert_to_bytes(img)
	}
	if img.bdata == nil do return nil
	n := img.image_width * img.image_height * img.bytes_per_pixel
	return img.bdata[:n]
}

// texture_image_float_slice returns a slice over the contiguous float
// RGB data for GPU upload (e.g. HDR SSBO). Length is
// width * height * bytes_per_pixel. Returns an empty slice if fdata
// is nil (e.g. LDR-only load).
texture_image_float_slice :: proc(img: ^Texture_Image) -> []f32 {
	if img == nil || img.fdata == nil do return nil
	n := img.image_width * img.image_height * img.bytes_per_pixel
	return img.fdata[:n]
}
