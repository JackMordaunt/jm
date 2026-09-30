/*
Package zstd is Zstandard compression over a statically linked libzstd 1.5.7,
plus binary patches built on zstd's prefix mode.

	// Whole buffers.
	packed := zstd.compress(buf[:], data, {level = 19}) or_return
	plain := zstd.decompress(out[:], packed) or_return

	// Streams, through fixed buffers on the stack.
	zstd.compress_stream(os.to_writer(dst), os.to_reader(src), {level = 19}) or_return
	zstd.decompress_stream(os.to_writer(dst), os.to_reader(src)) or_return

	// A patch that turns old into new, and applying it.
	zstd.diff(os.to_writer(p), old, new) or_return
	zstd.patch(os.to_writer(out), old, os.to_reader(p)) or_return

A patch is an ordinary zstd frame compressed with old as its prefix, the
format `zstd --patch-from` reads; checked by hand with the zstd 1.5.7 tool,
not by the tests, which do not assume it is installed. The frame
carries a checksum of new, so a patch applied to the wrong old fails with
.checksum_wrong or .corruption_detected instead of writing garbage silently.
diff sizes the window to reach from the end of new back to the start of old;
patch refuses a window over window_log_max, 27 (128 MiB) unless raised, which
covers any old and new that sum to less than that.

Memory: zstd's own tables and windows are allocated through Options.allocator,
context.allocator when it is left nil, and freed before each call returns.
Streaming reads and writes through two 64 KiB buffers on the stack. Nothing
else allocates. The allocator must be thread-safe only if the raw API is used
to set nbWorkers, which this wrapper never does.

The raw API is in ffi.odin under the C names.
*/
package zstd

import "base:runtime"
import "core:c"
import "core:io"
import "core:math/bits"
import "core:mem"

Code :: ZSTD_ErrorCode

// Error is zstd's own code or the error of the reader or writer it streamed
// through. nil is success.
Error :: union #shared_nil {
	Code,
	io.Error,
}

Options :: struct {
	// Compression level: 0 is zstd's default (3), 19 the strongest without
	// ultra, 22 the strongest; negative levels trade ratio for speed.
	level:          int,
	// Bytes both sides must hold. Compression finds matches in them;
	// decompression must be given the same bytes. The old file of a patch.
	prefix:         []byte,
	// Long-distance matching: finds repeats further back than the level's
	// window, at some cost in speed.
	long:           bool,
	// The largest window decompression accepts, as log2 bytes. 0 is 27.
	window_log_max: int,
	// Where zstd's tables go. nil is context.allocator.
	allocator:      mem.Allocator,
}

// CHUNK is the size of each stream buffer on the stack.
CHUNK :: 64 * mem.Kilobyte

// DIFF_LEVEL is the default level for diff: patches are made once, in CI,
// and applied many times, so the slow strong level pays for itself.
DIFF_LEVEL :: 19

version :: proc() -> string {
	return string(ZSTD_versionString())
}

// error_string names a Code for a message.
error_string :: proc(code: Code) -> string {
	return string(ZSTD_getErrorString(code))
}

// compress_bound is the largest compress output for n input bytes.
compress_bound :: proc(n: int) -> int {
	return int(ZSTD_compressBound(c.size_t(n)))
}

// content_size reads the decompressed size from a frame header, when the
// compressor wrote it.
content_size :: proc(src: []byte) -> (n: int, ok: bool) {
	size := ZSTD_getFrameContentSize(raw_data(src), c.size_t(len(src)))
	if size == CONTENTSIZE_UNKNOWN || size == CONTENTSIZE_ERROR || size > c.ulonglong(max(int)) {
		return 0, false
	}
	return int(size), true
}

// compress writes one frame holding src into dst and returns the part of dst
// used. dst of compress_bound(len(src)) bytes always suffices.
compress :: proc(dst, src: []byte, opts := Options{}) -> (out: []byte, err: Error) {
	rc := runtime_context(opts)
	cctx := ZSTD_createCCtx_advanced(custom_mem(&rc))
	if cctx == nil {
		return nil, .memory_allocation
	}
	defer ZSTD_freeCCtx(cctx)
	configure_cctx(cctx, opts) or_return
	n := ZSTD_compress2(cctx, raw_data(dst), c.size_t(len(dst)), raw_data(src), c.size_t(len(src)))
	check(n) or_return
	return dst[:n], nil
}

// decompress decodes every frame in src into dst and returns the part of dst
// used; content_size tells how large dst must be when the header records it.
decompress :: proc(dst, src: []byte, opts := Options{}) -> (out: []byte, err: Error) {
	rc := runtime_context(opts)
	dctx := ZSTD_createDCtx_advanced(custom_mem(&rc))
	if dctx == nil {
		return nil, .memory_allocation
	}
	defer ZSTD_freeDCtx(dctx)
	configure_dctx(dctx, opts) or_return
	n := ZSTD_decompressDCtx(dctx, raw_data(dst), c.size_t(len(dst)), raw_data(src), c.size_t(len(src)))
	check(n) or_return
	return dst[:n], nil
}

// compress_stream reads src to its end and writes one frame to dst.
compress_stream :: proc(dst: io.Writer, src: io.Reader, opts := Options{}) -> Error {
	rc := runtime_context(opts)
	cctx := ZSTD_createCCtx_advanced(custom_mem(&rc))
	if cctx == nil {
		return .memory_allocation
	}
	defer ZSTD_freeCCtx(cctx)
	configure_cctx(cctx, opts) or_return
	chunk: [CHUNK]byte
	for {
		n, rerr := io.read(src, chunk[:])
		if rerr != nil && rerr != .EOF {
			return rerr
		}
		last := rerr == .EOF
		pump(cctx, dst, chunk[:n], last) or_return
		if last {
			return nil
		}
	}
}

// decompress_stream reads frames from src to its end and writes what they
// hold to dst. Input that stops inside a frame is .srcSize_wrong.
decompress_stream :: proc(dst: io.Writer, src: io.Reader, opts := Options{}) -> Error {
	rc := runtime_context(opts)
	dctx := ZSTD_createDCtx_advanced(custom_mem(&rc))
	if dctx == nil {
		return .memory_allocation
	}
	defer ZSTD_freeDCtx(dctx)
	configure_dctx(dctx, opts) or_return
	in_buf, out_buf: [CHUNK]byte
	// Nonzero until a frame has ended and been flushed; an empty input has
	// no frame at all, so it starts unfinished.
	pending := c.size_t(1)
	// zstd.h: a full output buffer may leave decoded bytes inside zstd, so
	// call again. Against 1.5.7, dropping `|| full` failed none of the tests,
	// with or without a frame checksum; the contract is followed anyway. A
	// call on empty input with nothing to flush would open a new frame and
	// hide that the last one finished.
	full := false
	for {
		n, rerr := io.read(src, in_buf[:])
		if rerr != nil && rerr != .EOF {
			return rerr
		}
		input := ZSTD_inBuffer{raw_data(in_buf[:]), c.size_t(n), 0}
		for input.pos < input.size || full {
			output := ZSTD_outBuffer{raw_data(out_buf[:]), CHUNK, 0}
			pending = ZSTD_decompressStream(dctx, &output, &input)
			check(pending) or_return
			io.write_full(dst, out_buf[:output.pos]) or_return
			full = output.pos == output.size
		}
		if rerr == .EOF {
			break
		}
	}
	if pending != 0 {
		return .srcSize_wrong
	}
	return nil
}

// diff writes a patch to dst that turns old into new.
diff :: proc(
	dst: io.Writer,
	old, new: []byte,
	level := DIFF_LEVEL,
	allocator := context.allocator,
) -> Error {
	opts := Options {
		level     = level,
		prefix    = old,
		long      = true,
		allocator = allocator,
	}
	rc := runtime_context(opts)
	cctx := ZSTD_createCCtx_advanced(custom_mem(&rc))
	if cctx == nil {
		return .memory_allocation
	}
	defer ZSTD_freeCCtx(cctx)
	configure_cctx(cctx, opts) or_return
	// The window reaches from the end of new back to the start of old.
	window := clamp(bits.len(uint(len(old) + len(new))), WINDOWLOG_MIN, WINDOWLOG_MAX)
	check(ZSTD_CCtx_setParameter(cctx, .windowLog, c.int(window))) or_return
	check(ZSTD_CCtx_setPledgedSrcSize(cctx, c.ulonglong(len(new)))) or_return
	return pump(cctx, dst, new, true)
}

// patch reads a patch from src and writes to dst what it turns old into.
patch :: proc(
	dst: io.Writer,
	old: []byte,
	src: io.Reader,
	window_log_max := 0,
	allocator := context.allocator,
) -> Error {
	return decompress_stream(
		dst,
		src,
		{prefix = old, window_log_max = window_log_max, allocator = allocator},
	)
}

// ---- internals ----------------------------------------------------------

@(private)
check :: proc(result: c.size_t) -> Error {
	if ZSTD_isError(result) != 0 {
		return ZSTD_getErrorCode(result)
	}
	return nil
}

// runtime_context is the context zstd's allocation callbacks run in: the
// caller's, with the allocator the options name.
@(private)
runtime_context :: proc(opts: Options) -> runtime.Context {
	rc := context
	if opts.allocator.procedure != nil {
		rc.allocator = opts.allocator
	}
	return rc
}

@(private)
custom_mem :: proc(rc: ^runtime.Context) -> ZSTD_customMem {
	return {customAlloc = zstd_alloc, customFree = zstd_free, opaque = rc}
}

// zstd_alloc returns memory aligned as malloc's is, which zstd assumes.
@(private)
zstd_alloc :: proc "c" (opaque: rawptr, size: c.size_t) -> rawptr {
	context = (^runtime.Context)(opaque)^
	p, err := mem.alloc(int(size), 2 * align_of(rawptr))
	if err != nil {
		return nil
	}
	return p
}

@(private)
zstd_free :: proc "c" (opaque: rawptr, address: rawptr) {
	context = (^runtime.Context)(opaque)^
	mem.free(address)
}

@(private)
configure_cctx :: proc(cctx: ^ZSTD_CCtx, opts: Options) -> Error {
	level := opts.level == 0 ? CLEVEL_DEFAULT : opts.level
	check(ZSTD_CCtx_setParameter(cctx, .compressionLevel, c.int(level))) or_return
	check(ZSTD_CCtx_setParameter(cctx, .checksumFlag, 1)) or_return
	if opts.long {
		check(ZSTD_CCtx_setParameter(cctx, .enableLongDistanceMatching, 1)) or_return
	}
	if len(opts.prefix) > 0 {
		check(ZSTD_CCtx_refPrefix(cctx, raw_data(opts.prefix), c.size_t(len(opts.prefix)))) or_return
	}
	return nil
}

@(private)
configure_dctx :: proc(dctx: ^ZSTD_DCtx, opts: Options) -> Error {
	if opts.window_log_max != 0 {
		check(ZSTD_DCtx_setParameter(dctx, .windowLogMax, c.int(opts.window_log_max))) or_return
	}
	if len(opts.prefix) > 0 {
		check(ZSTD_DCtx_refPrefix(dctx, raw_data(opts.prefix), c.size_t(len(opts.prefix)))) or_return
	}
	return nil
}

// pump feeds src to the compressor and writes what comes out; last ends the
// frame once src is consumed.
@(private)
pump :: proc(cctx: ^ZSTD_CCtx, dst: io.Writer, src: []byte, last: bool) -> Error {
	out_buf: [CHUNK]byte
	input := ZSTD_inBuffer{raw_data(src), c.size_t(len(src)), 0}
	mode := ZSTD_EndDirective.end if last else .continue_
	for {
		output := ZSTD_outBuffer{raw_data(out_buf[:]), CHUNK, 0}
		remaining := ZSTD_compressStream2(cctx, &output, &input, mode)
		check(remaining) or_return
		io.write_full(dst, out_buf[:output.pos]) or_return
		done := remaining == 0 if last else input.pos == input.size
		if done {
			return nil
		}
	}
}
