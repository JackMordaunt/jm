/*
Package libcurl is the part of vendor:curl jm:http calls, either linked or
opened at run time. jm:http imports it in vendor:curl's place, under the same
name, so its calls read as they did.

By default it is vendor:curl itself: its procedures are aliases, and libcurl
is linked as vendor:curl links it. With -define:JM_HTTP_DLOPEN=true on Linux,
nothing links libcurl; load opens it on first use instead, so a program whose
only use of the network is occasional, a licence activation, starts on a
system without libcurl and says what is missing when the request is made.
libcurl's one ABI comes under two sonames, libcurl.so.4 (OpenSSL) and
libcurl-gnutls.so.4 (GnuTLS, Debian's libcurl3t64-gnutls package, per its
file list on packages.debian.org), and a desktop may carry either alone; load
takes whichever it finds first.

	if !libcurl.load() { return .No_Library }
	h := libcurl.easy_init()
*/
package libcurl

import curl "vendor:curl"

// DLOPEN opens libcurl at run time on Linux instead of linking it.
DLOPEN :: #config(JM_HTTP_DLOPEN, false)

CURL :: curl.CURL
CURLM :: curl.CURLM
code :: curl.code
slist :: curl.slist
off_t :: curl.off_t
write_callback :: curl.write_callback
ERROR_SIZE :: curl.ERROR_SIZE
GLOBAL_DEFAULT :: curl.GLOBAL_DEFAULT
WRITEFUNC_ERROR :: curl.WRITEFUNC_ERROR
