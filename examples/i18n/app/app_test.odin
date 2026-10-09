package i18n_app

import "core:os"
import "core:path/filepath"
import "core:testing"

import "jm:i18n"
import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../view"

@(private = "file")
WINDOW :: ops.Size{1180, 900}

// A language chosen from the globe's menu is saved, and the next start
// opens in it.
@(test)
test_the_chosen_language_opens_the_next_start :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("", "atlas-app-*", context.allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	defer delete(dir)
	path, _ := filepath.join({dir, "atlas.db"}, context.temp_allocator)
	defer free_all(context.temp_allocator)

	h: Host
	testing.expect(t, open(&h, path))
	locale := startup_locale(&h, {"C"})
	testing.expect_value(t, locale, i18n.Locale.English)
	{
		m: view.Model
		view.model_init(&m, locale, fluent.Fonts{}, save_language, &h)
		defer view.model_destroy(&m)
		p: ui.Probe
		ui.probe_init(&p, view.view, &m, WINDOW, allocator = context.temp_allocator)
		defer ui.probe_destroy(&p)
		_, found := ui.probe_find(&p, "Deutsch")
		testing.expect(t, !found) // the menu is closed
		testing.expect(t, ui.probe_click(&p, "English")) // the globe names the language in use
		ui.probe_advance(&p, 30, 0.02)
		testing.expect(t, ui.probe_click(&p, "Deutsch"))
		ui.probe_frame(&p)
		_, found = ui.probe_find(&p, "Startseite") // Home, in German
		testing.expect(t, found)
	}
	close(&h)

	testing.expect(t, open(&h, path))
	defer close(&h)
	testing.expect_value(t, startup_locale(&h, {"fr_FR.UTF-8"}), i18n.Locale.German)
}

@(test)
test_without_a_saved_language_the_system_s_is_used :: proc(t: ^testing.T) {
	h: Host
	testing.expect(t, open(&h, ":memory:"))
	defer close(&h)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, startup_locale(&h, {"", "ja_JP.UTF-8"}), i18n.Locale.Japanese)
	testing.expect_value(t, startup_locale(&h, {"C"}), i18n.Locale.English)
}
