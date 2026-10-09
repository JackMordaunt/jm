/*
Package i18n is the configuration and composition layer for an
application's translations. The application names its messages in an
enum, ships each locale's text inside the binary with #load, and loads
the one in use into a Table it indexes by that enum:

	Msg :: enum u16 { Save, Items_Selected }

	EN :: #load("locales/en.txt", string)
	DE :: #load("locales/de.txt", string)

	base, strings: i18n.Table(Msg)
	i18n.load(&base, .English, EN)
	i18n.load(&strings, .German, DE, &base) // what German leaves out comes from base

	i18n.text(&strings, Msg.Save) // "Speichern"
	i18n.format(&strings, Msg.Items_Selected, 3, allocator = gtx.allocator)

`i18n.text(&strings, .Save)` does not compile ("Cannot determine type
for implicit selector expression": K is not known while the argument is
checked), so an application wraps these in two procs of its own over its
enum, where `tr(.Save)` reads as it should.

A locale's text is one message per line, `key = text`, keys matched to
the enum's member names without regard to case. `key.one = text` is one
plural form (zero, one, two, few, many, other: the CLDR categories) and a
bare key is the other form. {0} to {9} are arguments, {{ a literal brace.
Lines starting with # are comments.

Nothing allocates after load. A message's text is a slice of the source,
which #load keeps for the life of the program, so text hands back a
string that outlives any frame. format writes into the allocator it is
given, in a ui the frame arena, and bformat into a caller's buffer. A
plural message picks its form by argument 0, under the locale's CLDR rule
for integers; an int argument is written with the locale's digits and
grouping. A Table is a fixed array of the enum's size: a lookup is one
index, and switching locale is one load, which parses a few kilobytes.

What a template cannot say: a translated word passed as an argument does
not agree with the sentence around it in gender or case, and there are no
select variants; dates and decimals have no locale formats yet. Layout
direction is the caller's: direction reports it, and jm:ui does not yet
mirror a row.
*/
package i18n

import "base:intrinsics"
import "core:strings"

// Plural is a CLDR plural category.
Plural :: enum u8 {
	Zero,
	One,
	Two,
	Few,
	Many,
	Other,
}

// Message is one message's text in each plural form it has; one that is
// not plural has only Other.
Message :: struct {
	forms: [Plural]string,
}

// Table is one locale's messages, indexed by the application's enum K,
// whose members must run from 0 without gaps.
Table :: struct($K: typeid) where intrinsics.type_is_enum(K) {
	locale:   Locale,
	messages: [K]Message,
}

// Arg is a message's argument: an int is written in the locale's digits
// and grouping, and as argument 0 it picks the plural form; a string is
// written as it is.
Arg :: union {
	int,
	string,
}

// MAX_ARGS is how many arguments a template can name, {0} to {9}.
MAX_ARGS :: 10

// table_locale is the locale table was loaded as.
table_locale :: proc(table: ^Table($K)) -> Locale {
	return table.locale
}

// text is key's message with no arguments filled in: its other form, a
// slice of the source table was loaded from.
text :: proc(table: ^Table($K), key: K) -> string {
	return table.messages[key].forms[.Other]
}

// form is key's text in plural form, or its other form where it has none.
form :: proc(table: ^Table($K), key: K, plural: Plural) -> string {
	message := &table.messages[key]
	if message.forms[plural] != "" {
		return message.forms[plural]
	}
	return message.forms[.Other]
}

// format is key's message with args filled in, in allocator: one exact
// allocation, or none when the template has no argument to fill, since
// the template itself is then the answer.
format :: proc(table: ^Table($K), key: K, args: ..Arg, allocator := context.temp_allocator) -> string {
	template := pick(table, key, args)
	if strings.index_byte(template, '{') < 0 {
		return template
	}
	measure: Writer
	expand(&measure, table.locale, template, args)
	buf, err := make([]u8, measure.count, allocator)
	if err != nil {
		return template
	}
	writer := Writer {
		buf = buf,
	}
	expand(&writer, table.locale, template, args)
	return string(buf)
}

// bformat writes key's message with args filled in to buf. ok is false
// when it did not fit; text is then as much as fits, cut at a whole
// character.
bformat :: proc(buf: []u8, table: ^Table($K), key: K, args: ..Arg) -> (text: string, ok: bool) {
	writer := Writer {
		buf = buf,
	}
	expand(&writer, table.locale, pick(table, key, args), args)
	if writer.count <= len(buf) {
		return string(buf[:writer.count]), true
	}
	return string(buf[:utf8_floor(buf)]), false
}

// pick is the form of key args call for: by argument 0 when it is an int.
@(private)
pick :: proc(table: ^Table($K), key: K, args: []Arg) -> string {
	if len(args) > 0 {
		if count, is_count := args[0].(int); is_count {
			return form(table, key, plural(table.locale, count))
		}
	}
	return table.messages[key].forms[.Other]
}

// Writer is where a template expands to. count is every byte written,
// those past the end of buf too, so a Writer with no buf measures.
@(private)
Writer :: struct {
	buf:   []u8,
	count: int,
}

@(private)
write_string :: proc(writer: ^Writer, text: string) {
	if writer.count < len(writer.buf) {
		copy(writer.buf[writer.count:], text)
	}
	writer.count += len(text)
}

// expand writes template with each {N} replaced by args[N]. A {N} past
// the end of args is written as it stands, so it shows.
@(private)
expand :: proc(writer: ^Writer, locale: Locale, template: string, args: []Arg) {
	start := 0
	ii := 0
	for ii < len(template) {
		if template[ii] != '{' {
			ii += 1
			continue
		}
		if ii + 1 < len(template) && template[ii + 1] == '{' {
			write_string(writer, template[start:ii + 1])
			ii += 2
			start = ii
			continue
		}
		if ii + 2 < len(template) && is_digit(template[ii + 1]) && template[ii + 2] == '}' {
			index := int(template[ii + 1] - '0')
			if index < len(args) {
				write_string(writer, template[start:ii])
				write_arg(writer, locale, args[index])
				start = ii + 3
			}
			ii += 3
			continue
		}
		ii += 1
	}
	write_string(writer, template[start:])
}

@(private)
write_arg :: proc(writer: ^Writer, locale: Locale, arg: Arg) {
	switch value in arg {
	case int:
		write_int(writer, LOCALES[locale].number, value)
	case string:
		write_string(writer, value)
	}
}

@(private)
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

// utf8_floor is where buf, holding a prefix of some text, ends on a
// whole character: before the last one when its bytes run past the end.
@(private)
utf8_floor :: proc(buf: []u8) -> int {
	lead := len(buf)
	for lead > 0 && buf[lead - 1] & 0xc0 == 0x80 {
		lead -= 1
	}
	if lead == 0 {
		return 0
	}
	lead -= 1
	width := 1
	switch {
	case buf[lead] >= 0xf0:
		width = 4
	case buf[lead] >= 0xe0:
		width = 3
	case buf[lead] >= 0xc0:
		width = 2
	}
	return len(buf) if lead + width <= len(buf) else lead
}
