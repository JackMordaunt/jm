#+build darwin
package files_fs

import "base:intrinsics"
import "core:c"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import "core:sys/posix"

foreign import libc "system:System.framework"

@(private = "file")
RENAME_EXCL :: 0x00000004

@(private = "file")
foreign libc {
	renamex_np :: proc "c" (from, to: cstring, flags: c.uint) -> c.int ---
}

@(private = "file", objc_class = "NSFileManager")
File_Manager :: struct {
	using _: NS.Object,
}

// rename_noreplace renames from to to, failing with Exists rather than
// replacing whatever is at to: renamex_np's RENAME_EXCL makes the check
// and the rename one step, so nothing can slip in between.
rename_noreplace :: proc(from, to: string) -> Error {
	f := strings.clone_to_cstring(from, context.temp_allocator)
	t := strings.clone_to_cstring(to, context.temp_allocator)
	if renamex_np(f, t, RENAME_EXCL) != 0 {
		return platform_error(i32(posix.errno()))
	}
	return .None
}

// trash moves path to the Trash with NSFileManager, as the Finder does,
// and returns where it went, in allocator.
trash :: proc(path: string, allocator := context.allocator) -> (trashed: string, err: Error) {
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	str := NS.String.alloc()->initWithOdinString(path)
	url := NS.URL.alloc()->initFileURLWithPath(str)
	fm := intrinsics.objc_send(^File_Manager, File_Manager, "defaultManager")
	result: ^NS.URL
	failure: ^NS.Error
	ok := intrinsics.objc_send(NS.BOOL, fm, "trashItemAtURL:resultingItemURL:error:", url, &result, &failure)
	if !bool(ok) {
		if failure != nil && failure->code() == 4 { 	// NSFileNoSuchFileError
			return "", .Missing
		}
		return "", .Other
	}
	if result == nil {
		return "", .None
	}
	location := intrinsics.objc_send(^NS.String, result, "path")
	return strings.clone(location->odinString(), allocator), .None
}

// restored is what remains to do once a trashed entry is back: nothing,
// on macOS.
restored :: proc(trashed: string) {}

platform_error :: proc(errno: i32) -> Error {
	#partial switch posix.Errno(errno) {
	case .EEXIST, .ENOTEMPTY:
		return .Exists
	case .ENOENT:
		return .Missing
	case .EACCES, .EPERM:
		return .Denied
	case .EXDEV:
		return .Cross_Device
	case .ENOTSUP:
		return .Unsupported
	}
	return .Other
}
