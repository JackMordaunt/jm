package libcurl

import "core:dynlib"
import "core:testing"

// Used only when DLOPEN is set.
_ :: dynlib

// A library that is not libcurl is refused, bind setting none of curl's
// procedures; then load finds libcurl, as on every system jm tests on, and
// sets them. One test, since both write the same procedures.
@(test)
load_refuses_what_is_not_libcurl :: proc(t: ^testing.T) {
	when DLOPEN {
		lib, ok := dynlib.load_library("libc.so.6")
		testing.expect(t, ok, "libc.so.6 must load")
		defer dynlib.unload_library(lib)
		testing.expect(t, !bind(lib))
		testing.expect(t, easy_init == nil && global_init == nil && multi_info_read == nil)

		if !testing.expect(t, load(), "no libcurl.so.4 or libcurl-gnutls.so.4") {
			return
		}
		testing.expect(t, easy_init != nil && easy_setopt != nil && multi_info_read != nil)
	}
}
