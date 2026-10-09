package i18n_view

import "core:testing"

import "jm:i18n"
import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../msg"

@(private = "file")
WINDOW :: ops.Size{1180, 900}

@(test)
test_every_page_draws_in_every_locale :: proc(t: ^testing.T) {
	m: Model
	model_init(&m, .English, fluent.Fonts{})
	defer model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	for locale in i18n.Locale {
		msg.use(&m.strings, locale)
		for page in Page {
			m.page = page
			ui.probe_frame(&p)
			_, found := ui.probe_find(&p, tr(&m, PAGE_TITLES[page]))
			testing.expectf(t, found, "%s %v: no title", i18n.locale_tag(locale), page)
		}
	}
}

@(test)
test_the_language_menu_lists_every_shipped_locale_in_its_own_name :: proc(t: ^testing.T) {
	chosen: i18n.Locale
	m: Model
	model_init(&m, .English, fluent.Fonts{}, proc(user: rawptr, locale: i18n.Locale) {
		(^i18n.Locale)(user)^ = locale
	}, &chosen)
	defer model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "English"))
	ui.probe_advance(&p, 30, 0.02)
	for locale in i18n.Locale {
		_, found := ui.probe_find(&p, i18n.locale_name(locale))
		testing.expectf(t, found, "%s is not in the menu", i18n.locale_name(locale))
	}
	testing.expect(t, ui.probe_click(&p, "日本語"))
	testing.expect_value(t, chosen, i18n.Locale.Japanese)
	ui.probe_advance(&p, 30, 0.02) // the toast's enter motion
	_, toasted := ui.probe_find(&p, tr(&m, .Changes_Saved))
	testing.expect(t, toasted)
	testing.expect(t, !m.language_open)
	ui.probe_frame(&p)
	_, found := ui.probe_find(&p, "日本語") // the globe now names it
	testing.expect(t, found)
}

@(test)
test_the_presets_reach_each_plural_form :: proc(t: ^testing.T) {
	m: Model
	model_init(&m, .Russian, fluent.Fonts{})
	defer model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	seen: bit_set[i18n.Plural]
	for preset in PRESETS {
		label := i18n.number(.Russian, preset)
		testing.expect(t, ui.probe_click(&p, label))
		testing.expect_value(t, m.selected, preset)
		ui.probe_frame(&p)
		want := msg.trf(&m.strings, .Items_Selected, preset)
		_, found := ui.probe_find(&p, want)
		testing.expectf(t, found, "no %q", want)
		seen += {i18n.plural(.Russian, preset)}
	}
	testing.expect_value(t, seen, bit_set[i18n.Plural]{.One, .Few, .Many})
}

@(test)
test_the_drawer_opens_a_page_by_its_translated_name :: proc(t: ^testing.T) {
	m: Model
	model_init(&m, .German, fluent.Fonts{})
	defer model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, tr(&m, .Nav_Team)))
	testing.expect_value(t, m.page, Page.Team)
	ui.probe_frame(&p)
	// A message carrying another: "Zuletzt aktiv: Vor 2 Stunden".
	want := msg.trf(&m.strings, .Last_Active, msg.trf(&m.strings, .Hours_Ago, 2))
	_, found := ui.probe_find(&p, want)
	testing.expectf(t, found, "no %q", want)
}

@(test)
test_the_presets_reach_every_form_each_locale_reaches :: proc(t: ^testing.T) {
	for locale in i18n.Locale {
		reached, wanted: bit_set[i18n.Plural]
		for preset in PRESETS {
			reached += {i18n.plural(locale, preset)}
		}
		for value in 0 ..= 1000 {
			wanted += {i18n.plural(locale, value)}
		}
		wanted += {i18n.plural(locale, 1_000_000)}
		testing.expectf(t, reached == wanted, "%s: presets reach %v of %v", i18n.locale_tag(locale), reached, wanted)
	}
}
