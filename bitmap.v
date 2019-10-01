module bitmap

import lobotony.ldata

#flag   -I @VROOT/thirdparty/stb_image
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#flag -I @VMOD/lobotony/stbiw
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"


struct Bitmap {
    pub:
    data byteptr        // points to the raw pixel data
    width u16           // width in pixels
    height u16          // height in pixels
    format Format       // format of bitmap (e.g. rgb, rgba)
    premultiplied bool  // true if alpha was premlultiplied, false otherwise
    loaded bool         // true if the image was loaded with the image library and data must be freed by it.
                        // false if data is just a chunk of memory and can simply be deleted
}

fn (self Bitmap) str() string {
    return 'Bitmap{data:${u64(self.data).str()} width:${self.width} height:${self.height} format:${self.format.str()} premultiplied:${self.premultiplied} loaded:${self.loaded}}'
}

pub fn init(width u16, height u16, format Format) Bitmap {
    size_in_bytes := u32(width) * u32(height) * u32(format.bytes_per_pixel())
    //println('allocating $size_in_bytes bytes for $width x $height ${format.str()}')
    return Bitmap{malloc(int(size_in_bytes)), width, height, format, false, false}
}

pub fn init_from_file(path string) Bitmap {
    file_contents := ldata.init_with_file(path)
    return init_from_data(file_contents)
}

pub fn init_from_data(buffer ldata.Data) Bitmap {
    
    mut w := int(0)
    mut h := int(0)
    mut channels := int(0)
    mut decoded := byteptr(0)
    decoded = C.stbi_load_from_memory(buffer.data, buffer.size, &w, &h, &channels, 4) // currently: always ask for rgba / 4-channel decode
    if decoded == 0 {
        panic('couldn\'t decode image data')
    }

    mut format := Format.undefined
    if channels == 1 {
        format = .a
    } else if channels == 3 {
        format = .rgb
    } else if channels == 4 {
        format = .rgba
    } else {
        panic('unsupported number of channels $channels')
    }

    return Bitmap{decoded, u16(w), u16(h), Format.rgba, false, true}
}

pub fn (self Bitmap) deinit() {
    if self.loaded {
        //println('freeing decoded bitmap data ${u64(self.data).str()}')
        C.stbi_image_free(self.data)
    } else {
        //println('freeing allocated bitmap data ${u64(self.data).str()}')
        free(self.data)
    }
    C.memset(&self, 0, sizeof(Bitmap))
}

pub fn (self Bitmap) premultiply() {
    if self.premultiplied {
        panic('already premultipled')
    }
    if self.format != .rgba {
        panic('can only premultiply rgba bitmaps')
    }
    mut pp := *u32(self.data)
    n := f32(1.0/255.0)
    for y := u16(0); y < self.height; y++ {
        for x := u16(0); x < self.width; x++ {
            i := int(y*self.width+x)
            mut p := pp[i]
            a := f32((p & u32(0xff000000))>>u32(24))*n
            mut b := f32((p & u32(0x00ff0000))>>u32(16))*n
            mut g := f32((p & u32(0x0000ff00))>>u32(8))*n
            mut r := f32((p & u32(0x000000ff)))*n

            r *= a
            g *= a
            b *= a

            p = u32(u32(a*255.0)<<u32(24)) |
                u32(u32(b*255.0)<<u32(16)) |
                u32(u32(g*255.0)<<u32(8)) |
                u32(r*255.0)

            pp[i] = p
        }
    }
}

pub fn (self Bitmap) clear(clearColor u32) {
    if self.format != .rgba {
        panic('clear currently only supported for .rgba')
    }

    mut p := *u32(self.data)
    for x := u16(0); x < self.width; x++ {
        for y := u16(0); y < self.height; y++ {
            i := y*self.width+x
            p[i] = clearColor
        }
    }
}

pub fn (self Bitmap) set_pixel(x u16, y u16, color u32) {
    if self.format != .rgba {
        panic('set_pixel only supported for rgba bitmaps')
    }
    i := y*self.width+x
    mut p := *u32(self.data)
    p[i] = color
}

pub fn (self Bitmap) flip_vertically() {
    bpp := u32(self.format.bytes_per_pixel())
    line_in_bytes := u32(self.width) * bpp
    half_height := u32(self.height) / u32(2) // deliberately round down if height is odd
    mut d := self.data
    for bottom_line := u32(0); bottom_line < half_height; bottom_line++ {
        top_line := u32(self.height) - u32(1) - bottom_line
        for bi := u32(0); bi < line_in_bytes; bi++ {
            top_line_byte := u32(self.width)*top_line*bpp+bi
            bottom_line_byte := u32(self.width)*bottom_line*bpp+bi
            b := d[top_line_byte]
            d[top_line_byte] = d[bottom_line_byte]
            d[bottom_line_byte] = b
        }
    }
}

pub fn (self Bitmap) write_to_file(path string) {
    bpp := self.format.bytes_per_pixel()
    result := C.stbi_write_png(path.str, int(self.width), int(self.height), int(bpp), self.data, int(bpp)*int(self.width))
    if C.NULL == result {
        panic('bitmap save failed: $path $self')
    }
}

enum Format {
    undefined,
    a,
    rgb,
    rgba
}

pub fn (self Format) str() string {
    mut s := 'unknown'
    if self == .undefined {
        s = 'undefined'
    } else if self == .a {
        s = 'a'
    } else if self == .rgb {
        s = 'rgb'
    } else if self == .rgba {
        s = 'rgba'
    }
    return 'Format{$s}'
}

fn (format Format) bytes_per_pixel() int {
    if format == .a {
        return 1
    } else if format == .rgb {
        return 3
    } else if format == .rgba {
        return 4
    } else {
        panic('can\'t derive bpp from format $format')
    }
}
