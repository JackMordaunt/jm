package example_common

import "core:fmt"
import "core:os"

// write_bmp writes pixels, width by height BGRA, as a 32-bit BMP: 54
// bytes of header and the rows top-down, so writing one needs no codec.
write_bmp :: proc(path: string, width, height: int, pixels: []u32) -> bool {
	row := width * 4
	size := 54 + row * height
	data := make([]u8, size, context.temp_allocator)
	put :: proc(d: []u8, at: int, v: u32) {
		d[at] = u8(v)
		d[at + 1] = u8(v >> 8)
		d[at + 2] = u8(v >> 16)
		d[at + 3] = u8(v >> 24)
	}
	data[0], data[1] = 'B', 'M'
	put(data, 2, u32(size))
	put(data, 10, 54)
	put(data, 14, 40)
	put(data, 18, u32(width))
	put(data, 22, u32(-height)) // top-down rows
	data[26], data[28] = 1, 32
	put(data, 34, u32(row * height))
	for p, ii in pixels {
		put(data, 54 + ii * 4, p)
	}
	if err := os.write_entire_file(path, data); err != nil {
		fmt.eprintln("write:", path, err)
		return false
	}
	return true
}
