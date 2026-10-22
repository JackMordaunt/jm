package libcurl

import "core:c"
import "core:dynlib"

import curl "vendor:curl"

// Used only when DLOPEN is set.
_ :: c
_ :: dynlib
_ :: curl

when DLOPEN {
	// SONAMES are the names libcurl's one ABI goes by, in the order tried.
	SONAMES :: [?]string{"libcurl.so.4", "libcurl-gnutls.so.4"}

	easy_init: proc "c" () -> ^CURL
	easy_setopt: proc "c" (h: ^CURL, option: curl.option, #c_vararg args: ..any) -> code
	easy_perform: proc "c" (h: ^CURL) -> code
	easy_cleanup: proc "c" (h: ^CURL)
	easy_getinfo: proc "c" (h: ^CURL, info: curl.INFO, #c_vararg args: ..any) -> code
	easy_strerror: proc "c" (c: code) -> cstring
	global_init: proc "c" (flags: c.long) -> code
	slist_append: proc "c" (list: ^slist, data: cstring) -> ^slist
	slist_free_all: proc "c" (list: ^slist)
	multi_init: proc "c" () -> ^CURLM
	multi_add_handle: proc "c" (m: ^CURLM, h: ^CURL) -> curl.Mcode
	multi_remove_handle: proc "c" (m: ^CURLM, h: ^CURL) -> curl.Mcode
	multi_poll: proc "c" (m: ^CURLM, extra_fds: [^]curl.waitfd, extra_nfds: c.uint, timeout_ms: c.int, ret: ^c.int) -> curl.Mcode
	multi_wakeup: proc "c" (m: ^CURLM) -> curl.Mcode
	multi_perform: proc "c" (m: ^CURLM, running: ^c.int) -> curl.Mcode
	multi_cleanup: proc "c" (m: ^CURLM) -> curl.Mcode
	multi_info_read: proc "c" (m: ^CURLM, queued: ^c.int) -> ^curl.Msg

	// load opens libcurl under the first of SONAMES the system has and finds
	// every procedure above in it, reporting whether it did. It is not safe to
	// call from two threads at once; jm:http calls it once, under a sync.Once.
	// A library missing any procedure is closed again and the next tried, so
	// either every procedure is set or none is called.
	load :: proc() -> bool {
		for name in SONAMES {
			lib, ok := dynlib.load_library(name)
			if !ok {
				continue
			}
			if bind(lib) {
				return true
			}
			dynlib.unload_library(lib)
		}
		return false
	}

	@(private)
	bind :: proc(lib: dynlib.Library) -> bool {
		Symbol :: struct {
			name: string,
			addr: ^rawptr,
		}
		table := [?]Symbol {
			{"curl_easy_init", (^rawptr)(&easy_init)},
			{"curl_easy_setopt", (^rawptr)(&easy_setopt)},
			{"curl_easy_perform", (^rawptr)(&easy_perform)},
			{"curl_easy_cleanup", (^rawptr)(&easy_cleanup)},
			{"curl_easy_getinfo", (^rawptr)(&easy_getinfo)},
			{"curl_easy_strerror", (^rawptr)(&easy_strerror)},
			{"curl_global_init", (^rawptr)(&global_init)},
			{"curl_slist_append", (^rawptr)(&slist_append)},
			{"curl_slist_free_all", (^rawptr)(&slist_free_all)},
			{"curl_multi_init", (^rawptr)(&multi_init)},
			{"curl_multi_add_handle", (^rawptr)(&multi_add_handle)},
			{"curl_multi_remove_handle", (^rawptr)(&multi_remove_handle)},
			{"curl_multi_poll", (^rawptr)(&multi_poll)},
			{"curl_multi_wakeup", (^rawptr)(&multi_wakeup)},
			{"curl_multi_perform", (^rawptr)(&multi_perform)},
			{"curl_multi_cleanup", (^rawptr)(&multi_cleanup)},
			{"curl_multi_info_read", (^rawptr)(&multi_info_read)},
		}
		for s in table {
			p, found := dynlib.symbol_address(lib, s.name)
			if !found {
				for t in table {
					t.addr^ = nil
				}
				return false
			}
			s.addr^ = p
		}
		return true
	}
}
