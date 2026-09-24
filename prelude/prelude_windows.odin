#+build windows
package prelude

import win32 "core:sys/windows"

// platform_init makes the console print UTF-8, which core:fmt writes, and
// honour the ANSI escape sequences that core:terminal/ansi emits.
platform_init :: proc() {
	win32.SetConsoleOutputCP(win32.CODEPAGE(win32.CP_UTF8))
	for which in ([2]win32.DWORD{win32.STD_OUTPUT_HANDLE, win32.STD_ERROR_HANDLE}) {
		h := win32.GetStdHandle(which)
		if h == win32.INVALID_HANDLE_VALUE || h == nil {
			continue
		}
		mode: win32.DWORD
		if win32.GetConsoleMode(h, &mode) {
			win32.SetConsoleMode(h, mode | win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
		}
	}
}
