package datagrid

import "core:strings"

// Delimited text: CSV for an export (RFC 4180) and tab-separated text for
// the clipboard, meant to be pasted into a spreadsheet's cells. Both quote
// a field as RFC 4180 does, so a reader gets back what was written (the
// tests read both back through core:encoding/csv): in double quotes, a
// quote inside doubled, whenever the field holds the delimiter, a quote,
// a carriage return or a newline.

// Delimited is a format: its delimiter and line ending, and whether a
// field that a spreadsheet would run as a formula is defused.
Delimited :: struct {
	delim:  u8,
	eol:    string,
	defuse: bool,
}

// CSV is an export to a file: commas, CRLF, formulas defused.
CSV :: Delimited{',', "\r\n", true}

// TSV is a copy to the clipboard: tabs and newlines, the cells as they
// are, so a copy pastes the text the grid shows, unchanged.
TSV :: Delimited{'\t', "\n", false}

// FORMULA_LEADERS are the first characters that can make a spreadsheet
// run a cell as a formula (OWASP's "CSV Injection" lists = + - @, tab and
// carriage return). A cell an export writes is often a customer's own text
// (a rig name, a note), so a defusing format puts an apostrophe before one
// and quotes the cell, as the admin dashboard's escape_csv_field does.
FORMULA_LEADERS :: "=+-@\t\r"

// write_field writes s as one field of f to b, quoted when it must be.
write_field :: proc(b: ^strings.Builder, f: Delimited, s: string) {
	defused := f.defuse && len(s) > 0 && strings.index_byte(FORMULA_LEADERS, s[0]) >= 0
	if !defused && !needs_quotes(s, f.delim) {
		strings.write_string(b, s)
		return
	}
	strings.write_byte(b, '"')
	if defused {
		strings.write_byte(b, '\'')
	}
	for i in 0 ..< len(s) {
		if s[i] == '"' {
			strings.write_byte(b, '"')
		}
		strings.write_byte(b, s[i])
	}
	strings.write_byte(b, '"')
}

// needs_quotes reports whether s, unquoted, would read back as something
// else.
@(private)
needs_quotes :: proc(s: string, delim: u8) -> bool {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '"', '\n', '\r':
			return true
		case delim:
			return true
		}
	}
	return false
}

// write_record writes fields as one record of f, its line ending after.
write_record :: proc(b: ^strings.Builder, f: Delimited, fields: []string) {
	if len(fields) == 1 && fields[0] == "" {
		// A blank line is no record to a reader; one empty field is "".
		strings.write_string(b, `""`)
		strings.write_string(b, f.eol)
		return
	}
	for s, i in fields {
		if i > 0 {
			strings.write_byte(b, f.delim)
		}
		write_field(b, f, s)
	}
	strings.write_string(b, f.eol)
}
