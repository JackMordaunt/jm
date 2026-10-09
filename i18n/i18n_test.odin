package i18n

import "core:testing"

@(private = "file")
Msg :: enum u8 {
	Save,
	Greeting,
	Files,
	Moved,
}

@(private = "file")
EN :: `# English
save = Save
greeting = Welcome back, {0}
files.one = {0} file
files.other = {0} files
moved = {0} moved {1} {{draft}
`

@(private = "file")
RU :: `save = Сохранить
greeting = С возвращением, {0}
files.one = {0} файл
files.few = {0} файла
files.many = {0} файлов
files.other = {0} файла
`

@(test)
test_load_reads_forms_and_falls_back_to_base :: proc(t: ^testing.T) {
	base, ru: Table(Msg)
	err, _ := load(&base, .English, EN)
	testing.expect_value(t, err, Load_Error.None)
	err, _ = load(&ru, .Russian, RU, &base)
	testing.expect_value(t, err, Load_Error.None)
	testing.expect_value(t, text(&ru, Msg.Save), "Сохранить")
	testing.expect_value(t, text(&ru, Msg.Moved), "{0} moved {1} {{draft}") // from base
	testing.expect_value(t, table_locale(&ru), Locale.Russian)
}

@(test)
test_format_picks_the_plural_form_by_argument_zero :: proc(t: ^testing.T) {
	base, ru: Table(Msg)
	load(&base, .English, EN)
	load(&ru, .Russian, RU, &base)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, format(&base, Msg.Files, 1), "1 file")
	testing.expect_value(t, format(&base, Msg.Files, 0), "0 files")
	testing.expect_value(t, format(&ru, Msg.Files, 1), "1 файл")
	testing.expect_value(t, format(&ru, Msg.Files, 3), "3 файла")
	testing.expect_value(t, format(&ru, Msg.Files, 11), "11 файлов")
	testing.expect_value(t, format(&ru, Msg.Files, 21), "21 файл")
	testing.expect_value(t, format(&ru, Msg.Files, 1234), "1 234 файла")
	testing.expect_value(t, format(&base, Msg.Moved, "Ana", "Plan"), "Ana moved Plan {draft}")
	testing.expect_value(t, format(&base, Msg.Moved, "Ana"), "Ana moved {1} {draft}") // a missing argument shows
}

@(test)
test_format_without_arguments_returns_the_template_itself :: proc(t: ^testing.T) {
	base: Table(Msg)
	load(&base, .English, EN)
	saved := format(&base, Msg.Save)
	testing.expect_value(t, raw_data(saved), raw_data(text(&base, Msg.Save)))
}

@(test)
test_bformat_cuts_at_a_whole_character :: proc(t: ^testing.T) {
	base, ru: Table(Msg)
	load(&base, .English, EN)
	load(&ru, .Russian, RU, &base)
	buf: [64]u8
	got, ok := bformat(buf[:], &ru, Msg.Greeting, "Аня")
	testing.expect(t, ok)
	testing.expect_value(t, got, "С возвращением, Аня")
	small: [4]u8 // "С " is three bytes; "в" would need two more
	got, ok = bformat(small[:], &ru, Msg.Greeting, "Аня")
	testing.expect(t, !ok)
	testing.expect_value(t, got, "С ")
}

@(test)
test_load_skips_bad_lines_and_reports_the_first :: proc(t: ^testing.T) {
	table: Table(Msg)
	err, line := load(&table, .English, "save = Save\nnonsense\nnope = x\nsave = Again\nfiles.lots = x\ngreeting = Hi\n")
	testing.expect_value(t, err, Load_Error.No_Equals)
	testing.expect_value(t, line, 2)
	testing.expect_value(t, text(&table, Msg.Save), "Save") // a duplicate keeps the first
	testing.expect_value(t, text(&table, Msg.Greeting), "Hi") // a good line after the bad ones still loads
}

@(test)
test_check_finds_missing_mismatched_and_formless :: proc(t: ^testing.T) {
	base: Table(Msg)
	load(&base, .English, EN)
	source := "save = Zapisz\ngreeting = Witaj\nfiles.one = {0} plik\nfiles.other = {0} pliku\nbogus\n"
	issues := check(Msg, .Polish, source, &base, context.temp_allocator)
	defer free_all(context.temp_allocator)
	want := [?]Issue {
		{kind = .Line, line = 5, error = .No_Equals},
		{kind = .Placeholders, key = "Greeting", form = .Other},
		{kind = .Form, key = "Files", form = .Few},
		{kind = .Form, key = "Files", form = .Many},
		{kind = .Missing, key = "Moved"},
	}
	testing.expect_value(t, len(issues), len(want))
	for issue, ii in issues[:min(len(issues), len(want))] {
		testing.expect_value(t, issue, want[ii])
	}
}

@(test)
test_plural_follows_cldr :: proc(t: ^testing.T) {
	Case :: struct {
		locale: Locale,
		count:  int,
		want:   Plural,
	}
	cases := [?]Case {
		{.English, 0, .Other},
		{.English, 1, .One},
		{.French, 0, .One},
		{.French, 2, .Other},
		{.French, 1_000_000, .Many},
		{.Spanish, 1_000_000, .Many},
		{.Spanish, 1_000_001, .Other},
		{.Polish, 1, .One},
		{.Polish, 22, .Few},
		{.Polish, 12, .Many},
		{.Polish, 21, .Many},
		{.Russian, 21, .One},
		{.Russian, 111, .Many},
		{.Ukrainian, 104, .Few},
		{.Arabic, 0, .Zero},
		{.Arabic, 2, .Two},
		{.Arabic, 103, .Few},
		{.Arabic, 111, .Many},
		{.Arabic, 100, .Other},
		{.Hindi, 0, .One},
		{.Japanese, 1, .Other},
		{.English, -1, .One},
	}
	for c in cases {
		testing.expectf(t, plural(c.locale, c.count) == c.want, "%v %d: got %v, want %v", c.locale, c.count, plural(c.locale, c.count), c.want)
	}
}

@(test)
test_numbers_use_the_locale_s_digits_and_grouping :: proc(t: ^testing.T) {
	Case :: struct {
		locale: Locale,
		value:  int,
		want:   string,
	}
	cases := [?]Case {
		{.English, 1234567, "1,234,567"},
		{.English, 999, "999"},
		{.English, -1234, "-1,234"},
		{.German, 1234, "1.234"},
		{.Spanish, 1234, "1234"},
		{.Spanish, 12345, "12.345"},
		{.French, 1234, "1 234"},
		{.Hindi, 1234567, "12,34,567"},
		{.Bengali, 1234, "১,২৩৪"},
		{.Arabic, 1234, "١٬٢٣٤"},
	}
	for c in cases {
		buf: [64]u8
		writer := Writer {
			buf = buf[:],
		}
		write_int(&writer, locale_number(c.locale), c.value)
		got := string(buf[:writer.count])
		testing.expectf(t, got == c.want, "%v %d: got %q, want %q", c.locale, c.value, got, c.want)
	}
}

@(test)
test_locale_match_reads_bcp47_and_posix_tags :: proc(t: ^testing.T) {
	Case :: struct {
		tag:  string,
		want: Locale,
		ok:   bool,
	}
	cases := [?]Case {
		{"de", .German, true},
		{"pt-BR", .Portuguese_Brazil, true},
		{"pt_PT.UTF-8", .Portuguese_Brazil, true},
		{"en_AU.UTF-8", .English, true},
		{"zh-Hant", .Chinese_Traditional, true},
		{"zh_TW.UTF-8", .Chinese_Traditional, true},
		{"zh_CN", .Chinese_Simplified, true},
		{"ZH-hans", .Chinese_Simplified, true},
		{"C", .English, false},
		{"", .English, false},
	}
	for c in cases {
		got, ok := locale_match(c.tag)
		testing.expectf(t, got == c.want && ok == c.ok, "%q: got %v %v, want %v %v", c.tag, got, ok, c.want, c.ok)
	}
	for locale in Locale {
		got, ok := locale_match(locale_tag(locale))
		testing.expect(t, ok && got == locale)
	}
}

@(test)
test_number_writes_a_bare_count :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, number(.Arabic, 21), "٢١")
	testing.expect_value(t, number(.English, 1_000_000), "1,000,000")
}
