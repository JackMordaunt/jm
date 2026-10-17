package libcurl

import curl "vendor:curl"

// Unused on Linux when DLOPEN is set.
_ :: curl

when ODIN_OS != .Linux || !DLOPEN {
	easy_init :: curl.easy_init
	easy_setopt :: curl.easy_setopt
	easy_perform :: curl.easy_perform
	easy_cleanup :: curl.easy_cleanup
	easy_getinfo :: curl.easy_getinfo
	easy_strerror :: curl.easy_strerror
	global_init :: curl.global_init
	slist_append :: curl.slist_append
	slist_free_all :: curl.slist_free_all
	multi_init :: curl.multi_init
	multi_add_handle :: curl.multi_add_handle
	multi_remove_handle :: curl.multi_remove_handle
	multi_poll :: curl.multi_poll
	multi_wakeup :: curl.multi_wakeup
	multi_perform :: curl.multi_perform
	multi_cleanup :: curl.multi_cleanup
	multi_info_read :: curl.multi_info_read

	// load reports whether libcurl is there to call: always, where it is
	// linked.
	load :: proc() -> bool {
		return true
	}
}
