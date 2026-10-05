#+build windows
package files_fs

import "core:strings"
import win32 "core:sys/windows"

// rename_noreplace renames from to to, failing with Exists rather than
// replacing whatever is at to: MoveFileExW without
// MOVEFILE_REPLACE_EXISTING never replaces, and without
// MOVEFILE_COPY_ALLOWED never copies between volumes.
rename_noreplace :: proc(from, to: string) -> Error {
	f := win32.utf8_to_wstring(from, context.temp_allocator)
	t := win32.utf8_to_wstring(to, context.temp_allocator)
	if !win32.MoveFileExW(f, t, 0) {
		return platform_error(i32(win32.GetLastError()))
	}
	return .None
}

// trash moves path to the Recycle Bin with the shell, as Explorer does.
// The shell does not say where it went, so the path returned is empty
// and Undo cannot bring it back.
trash :: proc(path: string, allocator := context.allocator) -> (trashed: string, err: Error) {
	wide := win32.utf8_to_utf16(path, context.temp_allocator)
	from := make([]u16, len(wide) + 2, context.temp_allocator) // the list ends in two NULs
	copy(from, wide)
	op := win32.SHFILEOPSTRUCTW {
		wFunc  = win32.FO_DELETE,
		pFrom  = cstring16(raw_data(from)),
		fFlags = win32.FOF_ALLOWUNDO | win32.FOF_NO_UI,
	}
	if win32.SHFileOperationW(&op) != 0 || op.fAnyOperationsAborted {
		return "", .Other
	}
	return "", .None
}

// restored is what remains to do once a trashed entry is back: nothing,
// since nothing is ever restored here.
restored :: proc(trashed: string) {}

// volume_of is the drive path is on, by its letter, or by its share for
// a UNC path.
volume_of :: proc(path: string) -> u64 {
	if len(path) >= 2 && path[1] == ':' {
		c := path[0]
		return u64(c - 32 if c >= 'a' && c <= 'z' else c)
	}
	if strings.has_prefix(path, `\\`) {
		h: u64 = 14695981039346656037
		parts := 0
		for c in transmute([]u8)path[2:] {
			if c == '\\' {
				parts += 1
				if parts == 2 {
					break
				}
			}
			h = (h ~ u64(c)) * 1099511628211
		}
		return h
	}
	return 0
}

@(private = "file")
ERROR_NOT_SAME_DEVICE :: 17

platform_error :: proc(code: i32) -> Error {
	switch u32(code) {
	case win32.ERROR_FILE_EXISTS, win32.ERROR_ALREADY_EXISTS:
		return .Exists
	case win32.ERROR_FILE_NOT_FOUND, win32.ERROR_PATH_NOT_FOUND:
		return .Missing
	case win32.ERROR_ACCESS_DENIED:
		return .Denied
	case ERROR_NOT_SAME_DEVICE:
		return .Cross_Device
	}
	return .Other
}
