package i18n

import "core:strings"
import "core:unicode/utf8"

// Locale is a locale this package knows the rules of: the languages most
// software ships, by speakers and by market (the UN's six official
// languages among them). Its CLDR facts, the plural rule for integers
// and the number format, are this package's; its text is the
// application's.
Locale :: enum u8 {
	English,
	Spanish,
	French,
	German,
	Italian,
	Portuguese_Brazil,
	Dutch,
	Polish,
	Russian,
	Ukrainian,
	Turkish,
	Arabic,
	Hindi,
	Bengali,
	Thai,
	Vietnamese,
	Indonesian,
	Japanese,
	Korean,
	Chinese_Simplified,
	Chinese_Traditional,
}

Direction :: enum u8 {
	Left_To_Right,
	Right_To_Left,
}

// Digits is the numbering system an int argument is written in.
Digits :: enum u8 {
	Latin,
	Arabic_Indic,
	Bengali,
}

// Number_Format is how a locale writes an integer (CLDR numbers):
// group between each group of digits, the first three from the right
// and then every three, or every two where indian. minimum_grouping is
// how many digits must lead the first separator: 2 leaves 1234 whole.
Number_Format :: struct {
	group:            string,
	digits:           Digits,
	indian:           bool,
	minimum_grouping: u8,
}

@(private)
Locale_Info :: struct {
	tag:       string, // BCP 47
	name:      string, // the language's own name for itself
	english:   string,
	direction: Direction,
	number:    Number_Format,
}

@(private)
NBSP :: " "
@(private)
NARROW_NBSP :: " "

@(private, rodata)
LOCALES := [Locale]Locale_Info {
	.English             = {"en", "English", "English", .Left_To_Right, {",", .Latin, false, 1}},
	.Spanish             = {"es", "Español", "Spanish", .Left_To_Right, {".", .Latin, false, 2}},
	.French              = {"fr", "Français", "French", .Left_To_Right, {NARROW_NBSP, .Latin, false, 1}},
	.German              = {"de", "Deutsch", "German", .Left_To_Right, {".", .Latin, false, 1}},
	.Italian             = {"it", "Italiano", "Italian", .Left_To_Right, {".", .Latin, false, 1}},
	.Portuguese_Brazil   = {"pt-BR", "Português (Brasil)", "Portuguese (Brazil)", .Left_To_Right, {".", .Latin, false, 1}},
	.Dutch               = {"nl", "Nederlands", "Dutch", .Left_To_Right, {".", .Latin, false, 1}},
	.Polish              = {"pl", "Polski", "Polish", .Left_To_Right, {NBSP, .Latin, false, 2}},
	.Russian             = {"ru", "Русский", "Russian", .Left_To_Right, {NBSP, .Latin, false, 1}},
	.Ukrainian           = {"uk", "Українська", "Ukrainian", .Left_To_Right, {NBSP, .Latin, false, 1}},
	.Turkish             = {"tr", "Türkçe", "Turkish", .Left_To_Right, {".", .Latin, false, 1}},
	.Arabic              = {"ar", "العربية", "Arabic", .Right_To_Left, {"٬", .Arabic_Indic, false, 1}},
	.Hindi               = {"hi", "हिन्दी", "Hindi", .Left_To_Right, {",", .Latin, true, 1}},
	.Bengali             = {"bn", "বাংলা", "Bengali", .Left_To_Right, {",", .Bengali, true, 1}},
	.Thai                = {"th", "ไทย", "Thai", .Left_To_Right, {",", .Latin, false, 1}},
	.Vietnamese          = {"vi", "Tiếng Việt", "Vietnamese", .Left_To_Right, {".", .Latin, false, 1}},
	.Indonesian          = {"id", "Bahasa Indonesia", "Indonesian", .Left_To_Right, {".", .Latin, false, 1}},
	.Japanese            = {"ja", "日本語", "Japanese", .Left_To_Right, {",", .Latin, false, 1}},
	.Korean              = {"ko", "한국어", "Korean", .Left_To_Right, {",", .Latin, false, 1}},
	.Chinese_Simplified  = {"zh-Hans", "简体中文", "Chinese (Simplified)", .Left_To_Right, {",", .Latin, false, 1}},
	.Chinese_Traditional = {"zh-Hant", "繁體中文", "Chinese (Traditional)", .Left_To_Right, {",", .Latin, false, 1}},
}

// locale_tag is locale's BCP 47 tag, the form to save it in.
locale_tag :: proc(locale: Locale) -> string {
	return LOCALES[locale].tag
}

// locale_name is the locale's language named in itself: what a language
// menu lists, since a reader looks for their own language by its own name.
locale_name :: proc(locale: Locale) -> string {
	return LOCALES[locale].name
}

// locale_english is the locale's language named in English.
locale_english :: proc(locale: Locale) -> string {
	return LOCALES[locale].english
}

locale_direction :: proc(locale: Locale) -> Direction {
	return LOCALES[locale].direction
}

locale_number :: proc(locale: Locale) -> Number_Format {
	return LOCALES[locale].number
}

// locale_match is the locale a tag names, a BCP 47 one ("pt-BR") or a
// POSIX one ("de_DE.UTF-8", as LANG holds): an exact tag first, then the
// language alone, so en-AU is English. Chinese goes by script, or by
// region where there is none: TW, HK and MO read Traditional.
locale_match :: proc(tag: string) -> (locale: Locale, ok: bool) {
	clean := tag
	if cut := strings.index_any(clean, ".@"); cut >= 0 {
		clean = clean[:cut]
	}
	buf: [32]u8
	size := min(len(clean), len(buf))
	for ii in 0 ..< size {
		buf[ii] = clean[ii] == '_' ? '-' : clean[ii]
	}
	normal := string(buf[:size])
	if normal == "" {
		return .English, false
	}
	for candidate in Locale {
		if strings.equal_fold(LOCALES[candidate].tag, normal) {
			return candidate, true
		}
	}
	language, _, rest := strings.partition(normal, "-")
	if strings.equal_fold(language, "zh") {
		for part in strings.split_iterator(&rest, "-") {
			if strings.equal_fold(part, "Hant") || strings.equal_fold(part, "TW") || strings.equal_fold(part, "HK") || strings.equal_fold(part, "MO") {
				return .Chinese_Traditional, true
			}
		}
		return .Chinese_Simplified, true
	}
	for candidate in Locale {
		own, _, _ := strings.partition(LOCALES[candidate].tag, "-")
		if strings.equal_fold(own, language) {
			return candidate, true
		}
	}
	return .English, false
}

// plural is the CLDR plural category of the integer count in locale
// (CLDR plurals.xml, integer operands: v = 0, e = 0).
plural :: proc(locale: Locale, count: int) -> Plural {
	value := magnitude(count)
	ones, hundreds := value % 10, value % 100
	switch locale {
	case .English, .German, .Dutch, .Turkish:
		return .One if value == 1 else .Other
	case .Spanish, .Italian:
		return .One if value == 1 else whole_million(value)
	case .French, .Portuguese_Brazil:
		return .One if value <= 1 else whole_million(value)
	case .Hindi, .Bengali:
		return .One if value <= 1 else .Other
	case .Russian, .Ukrainian:
		if ones == 1 && hundreds != 11 {
			return .One
		}
		if ones >= 2 && ones <= 4 && (hundreds < 12 || hundreds > 14) {
			return .Few
		}
		return .Many
	case .Polish:
		if value == 1 {
			return .One
		}
		if ones >= 2 && ones <= 4 && (hundreds < 12 || hundreds > 14) {
			return .Few
		}
		return .Many
	case .Arabic:
		switch {
		case value == 0:
			return .Zero
		case value == 1:
			return .One
		case value == 2:
			return .Two
		case hundreds >= 3 && hundreds <= 10:
			return .Few
		case hundreds >= 11:
			return .Many
		}
		return .Other
	case .Thai, .Vietnamese, .Indonesian, .Japanese, .Korean, .Chinese_Simplified, .Chinese_Traditional:
		return .Other
	}
	return .Other
}

// whole_million is many for a whole non-zero million, the form Spanish,
// French, Italian and Portuguese give "1 000 000 de"; other otherwise.
@(private)
whole_million :: proc(value: u64) -> Plural {
	return .Many if value != 0 && value % 1_000_000 == 0 else .Other
}

@(private)
magnitude :: proc(value: int) -> u64 {
	return u64(value) if value >= 0 else u64(-(value + 1)) + 1
}

// write_int writes value in format: its digits, grouped.
@(private)
write_int :: proc(writer: ^Writer, format: Number_Format, value: int) {
	if value < 0 {
		write_string(writer, "-")
	}
	rest := magnitude(value)
	reversed: [20]u8
	count := 0
	for {
		reversed[count] = u8(rest % 10)
		count += 1
		rest /= 10
		if rest == 0 {
			break
		}
	}
	grouped := count >= 3 + int(format.minimum_grouping)
	for position := count - 1; position >= 0; position -= 1 {
		write_digit(writer, format.digits, reversed[position])
		if grouped && position > 0 && group_ends(format.indian, position) {
			write_string(writer, format.group)
		}
	}
}

// group_ends is whether a separator follows the digit position places
// from the right.
@(private)
group_ends :: proc(indian: bool, position: int) -> bool {
	if indian {
		return position == 3 || (position > 3 && (position - 3) % 2 == 0)
	}
	return position % 3 == 0
}

@(private)
write_digit :: proc(writer: ^Writer, digits: Digits, digit: u8) {
	zero: rune
	switch digits {
	case .Latin:
		zero = '0'
	case .Arabic_Indic:
		zero = '٠'
	case .Bengali:
		zero = '০'
	}
	bytes, width := utf8.encode_rune(zero + rune(digit))
	write_string(writer, string(bytes[:width]))
}

// number is value in locale's digits and grouping, in allocator: for a
// count shown on its own, outside any message.
number :: proc(locale: Locale, value: int, allocator := context.temp_allocator) -> string {
	measure: Writer
	write_int(&measure, LOCALES[locale].number, value)
	buf, err := make([]u8, measure.count, allocator)
	if err != nil {
		return ""
	}
	writer := Writer {
		buf = buf,
	}
	write_int(&writer, LOCALES[locale].number, value)
	return string(buf)
}
