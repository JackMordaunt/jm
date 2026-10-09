package msg

import "core:testing"

import "jm:i18n"

@(test)
test_every_locale_translates_every_message :: proc(t: ^testing.T) {
	base: i18n.Table(Msg)
	err, line := i18n.load(&base, .English, SOURCES[.English])
	testing.expectf(t, err == .None, "en.txt line %d: %v", line, err)
	defer free_all(context.temp_allocator)
	for locale in i18n.Locale {
		if !shipped(locale) {
			continue
		}
		for issue in i18n.check(Msg, locale, SOURCES[locale], &base, context.temp_allocator) {
			testing.expectf(t, false, "%s: %v", i18n.locale_tag(locale), issue)
		}
	}
}

@(test)
test_every_known_locale_ships :: proc(t: ^testing.T) {
	for locale in i18n.Locale {
		testing.expectf(t, shipped(locale), "%s has no locales/%s.txt", i18n.locale_english(locale), i18n.locale_tag(locale))
	}
}

@(test)
test_use_switches_and_formats_in_the_locale :: proc(t: ^testing.T) {
	s: Strings
	init(&s, .English)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, tr(&s, .Save), "Save")
	testing.expect_value(t, trf(&s, .Files_Count, 1234567), "1,234,567 files")
	use(&s, .German)
	testing.expect_value(t, locale(&s), i18n.Locale.German)
	testing.expect(t, tr(&s, .Save) != "Save")
	testing.expect_value(t, trf(&s, .Storage_Used, 1536, 2048), "1.536 von 2.048 GB verwendet")
}
