package libcurl

import "core:dynlib"
import "core:testing"

// Used only when DLOPEN is set.
_ :: dynlib

// A library that is not libcurl is refused and bind leaves curl's procedures
// as they were. Another test may be calling them as this one runs (the
// tests of a program run at once), so clearing them, even for a moment, was a
// segmentation fault in whichever test made a request just then.
@(test)
load_refuses_what_is_not_libcurl :: proc(t: ^testing.T) {
	when DLOPEN {
		if !testing.expect(t, load(), "no libcurl.so.4 or libcurl-gnutls.so.4") {
			return
		}
		testing.expect(t, easy_init != nil && easy_setopt != nil && multi_info_read != nil)
		init, setopt, info := easy_init, easy_setopt, multi_info_read

		lib, ok := dynlib.load_library("libc.so.6")
		testing.expect(t, ok, "libc.so.6 must load")
		defer dynlib.unload_library(lib)

		testing.expect(t, !bind(lib))
		testing.expect(t, easy_init == init && easy_setopt == setopt && multi_info_read == info)
		testing.expect(t, load(), "load answers the same again")
	}
}
