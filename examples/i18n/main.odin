/*
Atlas is a small project-management app in every language jm:i18n knows:
twenty-one locales, a hundred messages each, chosen from the globe in the
top bar and remembered in SQLite for the next start. The pieces are
examples/i18n's packages:

	msg    the messages, and each locale's text      (data)
	store  the SQLite settings: read, write          (io)
	app    the host: which language to open in       (io)
	view   the ui                                    (ui)

This is the window around app.

	i18n                open atlas.db in the working directory
	i18n path.db        another database
	i18n -memory        a database that is gone when the window closes
*/
package main

import "core:os"

import "jm:sqlite3"
import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"
import "jm:ui/shell"

import "app"
import "view"

WIDTH :: 1180
HEIGHT :: 900

// Script is a font the window opens: the ui's two weights, then one font
// per script the Latin one lacks, which the shaper falls back to in order.
Script :: enum u8 {
	Regular,
	Bold,
	Arabic,
	Devanagari,
	Bengali,
	Thai,
	CJK,
}

// FONT_FILES is where each script's font may be, per platform; the first
// that exists is used, and a script with none falls back to
// ui.default_font.
FONT_FILES := [Script][]string {
	.Regular    = {"/usr/share/fonts/noto/NotoSans-Regular.ttf", "/System/Library/Fonts/SFNS.ttf", "C:/Windows/Fonts/segoeui.ttf"},
	.Bold       = {"/usr/share/fonts/noto/NotoSans-Bold.ttf", "/System/Library/Fonts/SFNS.ttf", "C:/Windows/Fonts/segoeuib.ttf"},
	.Arabic     = {"/usr/share/fonts/noto/NotoSansArabic-Regular.ttf", "/System/Library/Fonts/GeezaPro.ttc", "C:/Windows/Fonts/tahoma.ttf"},
	.Devanagari = {"/usr/share/fonts/noto/NotoSansDevanagari-Regular.ttf", "/System/Library/Fonts/Kohinoor.ttc", "C:/Windows/Fonts/Nirmala.ttc"},
	.Bengali    = {"/usr/share/fonts/noto/NotoSansBengali-Regular.ttf", "/System/Library/Fonts/KohinoorBangla.ttc", "C:/Windows/Fonts/Nirmala.ttc"},
	.Thai       = {"/usr/share/fonts/noto/NotoSansThai-Regular.ttf", "/System/Library/Fonts/Thonburi.ttc", "C:/Windows/Fonts/LeelawUI.ttf"},
	.CJK        = {"/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/System/Library/Fonts/PingFang.ttc", "C:/Windows/Fonts/msyh.ttc"},
}

main :: proc() {
	path := "atlas.db"
	if len(os.args) > 1 {
		path = os.args[1]
		if path == "-memory" {
			path = sqlite3.MEMORY
		}
	}
	h: app.Host
	if !app.open(&h, path) {
		os.exit(1)
	}
	defer app.close(&h)
	system := [3]string{os.get_env("LC_ALL", context.temp_allocator), os.get_env("LC_MESSAGES", context.temp_allocator), os.get_env("LANG", context.temp_allocator)}
	locale := app.startup_locale(&h, system[:])

	sc: ops.Scene
	ops.init(&sc)
	ids: [Script]ops.Font_Id
	for script in Script {
		file := ui.default_font()
		for candidate in FONT_FILES[script] {
			if os.exists(candidate) {
				file = candidate
				break
			}
		}
		ids[script] = ops.add_font(&sc, file)
	}
	fallbacks := [?]ops.Font_Id{ids[.Arabic], ids[.Devanagari], ids[.Bengali], ids[.Thai], ids[.CJK]}

	m: view.Model
	view.model_init(&m, locale, fluent.Fonts{ids[.Regular], ids[.Bold], ids[.Bold]}, app.save_language, &h)
	defer view.model_destroy(&m)
	shell.run({title = "Atlas", width = WIDTH, height = HEIGHT, min_width = 900, min_height = 640, ui = view.view, user = &m, fonts = sc.fonts[:], fallbacks = fallbacks[:]})
}
