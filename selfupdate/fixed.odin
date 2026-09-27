package selfupdate

import "core:io"

// Fixed is a byte buffer of a fixed capacity, filled through an io.Writer.
// A write past the end fails rather than growing, so the caller sees a
// file larger than expected as an error instead of an allocation.
Fixed :: struct($N: int) {
	data: [N]byte,
	len:  int,
}

fixed_writer :: proc(f: ^Fixed($N)) -> io.Writer {
	return io.Writer{procedure = fixed_stream_proc(N), data = f}
}

fixed_string :: proc(f: ^Fixed($N)) -> string {
	return string(f.data[:f.len])
}

fixed_bytes :: proc(f: ^Fixed($N)) -> []byte {
	return f.data[:f.len]
}

@(private)
fixed_stream_proc :: proc($N: int) -> io.Stream_Proc {
	return proc(data: rawptr, mode: io.Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From) -> (n: i64, err: io.Error) {
		f := (^Fixed(N))(data)
		#partial switch mode {
		case .Write:
			if f.len + len(p) > N {
				return 0, .Short_Write
			}
			copy(f.data[f.len:], p)
			f.len += len(p)
			return i64(len(p)), nil
		case .Query:
			return io.query_utility({.Write, .Query})
		}
		return 0, .Empty
	}
}
