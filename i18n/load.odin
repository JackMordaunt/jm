package i18n

import "core:reflect"
import "core:strings"

// Load_Error is what was wrong with a line of a locale's source.
Load_Error :: enum u8 {
	None,
	No_Equals, // neither blank, a comment, nor key = text
	Unknown_Key, // no member of the enum by that name
	Unknown_Form, // a .suffix that is not a plural category
	Duplicate, // the same key and form a second time
}

// load parses source, a locale's text, into table as locale. A message
// source leaves out, or gives no other form, is base's whole when base
// is given, so a lookup never needs a fallback. A bad line is skipped and
// the rest still load; err and line are the first. Nothing is allocated:
// table's strings are slices of source.
load :: proc(table: ^Table($K), locale: Locale, source: string, base: ^Table(K) = nil) -> (err: Load_Error, line: int) {
	err, line = parse(table, locale, source, nil)
	if base != nil {
		for key in K {
			if table.messages[key].forms[.Other] == "" {
				table.messages[key] = base.messages[key]
			}
		}
	}
	return
}

Issue_Kind :: enum u8 {
	Line, // a line load skipped: error says why
	Missing, // a message with no other form
	Placeholders, // a form naming other arguments than base's message
	Form, // a plural message without a form its locale needs for some count
}

// Issue is one thing check found. key is the enum member's name; form
// is the plural form for Placeholders and Form.
Issue :: struct {
	kind:  Issue_Kind,
	key:   string,
	form:  Plural,
	line:  int,
	error: Load_Error,
}

// check is what is wrong with source as locale's translation of base,
// for a test to fail on: every line load would skip, every message
// source leaves out, every form naming other arguments than base's, and
// every plural form a count from 0 to 1000, or a whole million, would
// fall back to other for. base is the source language, loaded.
check :: proc($K: typeid, locale: Locale, source: string, base: ^Table(K), allocator := context.allocator) -> []Issue {
	issues := make([dynamic]Issue, allocator)
	table := new(Table(K), allocator)
	defer free(table, allocator)
	parse(table, locale, source, &issues)
	for key in K {
		name, _ := reflect.enum_name_from_value(key)
		translated := &table.messages[key]
		if translated.forms[.Other] == "" {
			append(&issues, Issue{kind = .Missing, key = name})
			continue
		}
		wanted := placeholders(base.messages[key].forms[.Other])
		for text, form in translated.forms {
			if text != "" && placeholders(text) != wanted {
				append(&issues, Issue{kind = .Placeholders, key = name, form = form})
			}
		}
		if !is_plural(&base.messages[key]) {
			continue
		}
		needed: bit_set[Plural]
		for count in 0 ..= 1000 {
			needed += {plural(locale, count)}
		}
		needed += {plural(locale, 1_000_000), plural(locale, 2_000_000)}
		for form in needed {
			if translated.forms[form] == "" {
				append(&issues, Issue{kind = .Form, key = name, form = form})
			}
		}
	}
	return issues[:]
}

// placeholders is the set of arguments text names.
placeholders :: proc(text: string) -> (named: bit_set[0 ..< MAX_ARGS]) {
	for ii := 0; ii + 2 < len(text); ii += 1 {
		if text[ii] == '{' && text[ii + 1] == '{' {
			ii += 1
			continue
		}
		if text[ii] == '{' && is_digit(text[ii + 1]) && text[ii + 2] == '}' {
			named += {int(text[ii + 1] - '0')}
		}
	}
	return
}

// is_plural is whether message has a form besides other.
@(private)
is_plural :: proc(message: ^Message) -> bool {
	for text, form in message.forms {
		if form != .Other && text != "" {
			return true
		}
	}
	return false
}

@(private)
parse :: proc(table: ^Table($K), locale: Locale, source: string, issues: ^[dynamic]Issue) -> (first: Load_Error, first_line: int) {
	table.locale = locale
	table.messages = {}
	seen: [K]bit_set[Plural]
	rest := source
	number := 0
	for raw in strings.split_lines_iterator(&rest) {
		number += 1
		entry := strings.trim_space(raw)
		if entry == "" || entry[0] == '#' {
			continue
		}
		err := Load_Error.None
		defer if err != .None {
			if first == .None {
				first, first_line = err, number
			}
			if issues != nil {
				append(issues, Issue{kind = .Line, line = number, error = err})
			}
		}
		equals := strings.index_byte(entry, '=')
		if equals < 0 {
			err = .No_Equals
			continue
		}
		name := strings.trim_space(entry[:equals])
		form := Plural.Other
		if dot := strings.index_byte(name, '.'); dot >= 0 {
			ok: bool
			if form, ok = plural_from_name(name[dot + 1:]); !ok {
				err = .Unknown_Form
				continue
			}
			name = name[:dot]
		}
		key, found := key_from_name(K, name)
		if !found {
			err = .Unknown_Key
			continue
		}
		if form in seen[key] {
			err = .Duplicate
			continue
		}
		seen[key] += {form}
		table.messages[key].forms[form] = strings.trim_space(entry[equals + 1:])
	}
	return
}

// key_from_name is the member of K named name, without regard to case:
// a scan of K's names, which load does once a line.
@(private)
key_from_name :: proc($K: typeid, name: string) -> (K, bool) {
	values := reflect.enum_field_values(K)
	for field, ii in reflect.enum_field_names(K) {
		if strings.equal_fold(field, name) {
			return K(values[ii]), true
		}
	}
	return {}, false
}

@(private)
plural_from_name :: proc(name: string) -> (Plural, bool) {
	for form in Plural {
		form_name, _ := reflect.enum_name_from_value(form)
		if strings.equal_fold(form_name, name) {
			return form, true
		}
	}
	return .Other, false
}
