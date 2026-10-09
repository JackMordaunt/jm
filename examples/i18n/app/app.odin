/*
Package app is Atlas's host: it owns the settings store, decides the
language a window opens in, and saves the one the ui chooses.
*/
package i18n_app

import "jm:i18n"

import "../msg"
import "../store"

Host :: struct {
	store: store.Store,
}

open :: proc(h: ^Host, path: string) -> bool {
	return store.open(&h.store, path)
}

close :: proc(h: ^Host) {
	store.close(&h.store)
}

// startup_locale is the language to open in: the one saved last, else the
// first tag of system, in the order given, that names a language Atlas
// ships, else English. main passes LC_ALL, LC_MESSAGES and LANG, the
// order POSIX gives them precedence in (XBD 8.2).
startup_locale :: proc(h: ^Host, system: []string) -> i18n.Locale {
	if tag, found := store.setting(&h.store, store.LANGUAGE, context.temp_allocator); found {
		if locale, ok := i18n.locale_match(tag); ok && msg.shipped(locale) {
			return locale
		}
	}
	for tag in system {
		if locale, ok := i18n.locale_match(tag); ok && msg.shipped(locale) {
			return locale
		}
	}
	return .English
}

// save_language is the view's on_language: it saves locale's tag, with
// user the Host.
save_language :: proc(user: rawptr, locale: i18n.Locale) {
	h := (^Host)(user)
	store.set_setting(&h.store, store.LANGUAGE, i18n.locale_tag(locale))
}
