package main

import "core:fmt"
import "core:strconv"
import "core:strings"

// The formula language: a cell is empty, a number, text, or "=" and an
// expression of numbers, cell references (A1), + - * /, parentheses, and
// SUM, AVG, MIN and MAX over arguments and ranges (A1:B3).
//
//	=A1 + B2 * 2
//	=SUM(A0:A9) / AVG(B0, B1, 10)

COLS :: 26
ROWS :: 100

Cell :: struct {
	col, row: int,
}

Value_Kind :: enum u8 {
	Empty,
	Number,
	Text,
	Error,
}

Value :: struct {
	kind: Value_Kind,
	num:  f64,
}

// Sheet is the sources typed into the cells and the values computed from
// them; recompute brings the values up to date with the sources.
Sheet :: struct {
	source: [ROWS][COLS]string,
	value:  [ROWS][COLS]Value,
	state:  [ROWS][COLS]Eval_State,
}

Eval_State :: enum u8 {
	Stale,
	Busy, // being evaluated: a reference back to it is a cycle
	Done,
}

sheet_set :: proc(s: ^Sheet, c: Cell, text: string) {
	delete(s.source[c.row][c.col])
	s.source[c.row][c.col] = strings.clone(text)
	recompute(s)
}

sheet_destroy :: proc(s: ^Sheet) {
	for &row in s.source {
		for src in row {
			delete(src)
		}
	}
}

// recompute evaluates every cell, each once: a cell evaluates the cells it
// refers to first, so any order reaches the same values, and a cell met
// again while it is still being evaluated is in a cycle and an error.
recompute :: proc(s: ^Sheet) {
	s.state = {}
	for r in 0 ..< ROWS {
		for c in 0 ..< COLS {
			eval_cell(s, {c, r})
		}
	}
}

eval_cell :: proc(s: ^Sheet, c: Cell) -> Value {
	switch s.state[c.row][c.col] {
	case .Done:
		return s.value[c.row][c.col]
	case .Busy:
		return {kind = .Error}
	case .Stale:
	}
	s.state[c.row][c.col] = .Busy
	v := eval_source(s, s.source[c.row][c.col])
	s.value[c.row][c.col] = v
	s.state[c.row][c.col] = .Done
	return v
}

eval_source :: proc(s: ^Sheet, src: string) -> Value {
	t := strings.trim_space(src)
	if t == "" {
		return {}
	}
	if !strings.has_prefix(t, "=") {
		if n, ok := strconv.parse_f64(t); ok {
			return {.Number, n}
		}
		return {kind = .Text}
	}
	p := Parser{s, t[1:], 0}
	n, ok := expr(&p)
	skip_space(&p)
	if !ok || p.at != len(p.src) {
		return {kind = .Error}
	}
	return {.Number, n}
}

Parser :: struct {
	sheet: ^Sheet,
	src:   string,
	at:    int,
}

// expr is terms joined by + and -, left to right.
expr :: proc(p: ^Parser) -> (v: f64, ok: bool) {
	v = term(p) or_return
	for {
		switch peek(p) {
		case '+':
			p.at += 1
			v += term(p) or_return
		case '-':
			p.at += 1
			v -= term(p) or_return
		case:
			return v, true
		}
	}
}

// term is factors joined by * and /, left to right; dividing by zero is
// an error.
term :: proc(p: ^Parser) -> (v: f64, ok: bool) {
	v = factor(p) or_return
	for {
		switch peek(p) {
		case '*':
			p.at += 1
			v *= factor(p) or_return
		case '/':
			p.at += 1
			d := factor(p) or_return
			if d == 0 {
				return 0, false
			}
			v /= d
		case:
			return v, true
		}
	}
}

// factor is a number, a negated factor, an expression in parentheses, a
// cell reference, or a function call.
factor :: proc(p: ^Parser) -> (v: f64, ok: bool) {
	switch ch := peek(p); {
	case ch == '-':
		p.at += 1
		v = factor(p) or_return
		return -v, true
	case ch == '(':
		p.at += 1
		v = expr(p) or_return
		expect(p, ')') or_return
		return v, true
	case is_digit(ch) || ch == '.':
		return number(p)
	case is_letter(ch):
		start := p.at
		for p.at < len(p.src) && (is_letter(p.src[p.at]) || is_digit(p.src[p.at])) {
			p.at += 1
		}
		word := p.src[start:p.at]
		if peek(p) == '(' {
			return call(p, word)
		}
		c := parse_cell(word) or_return
		return number_at(p.sheet, c)
	}
	return 0, false
}

// call is a function applied to its comma-separated arguments, each a
// range or an expression.
call :: proc(p: ^Parser, name: string) -> (v: f64, ok: bool) {
	expect(p, '(') or_return
	acc := Tally{lo = max(f64), hi = min(f64)}
	for {
		fold_arg(p, &acc) or_return
		if peek(p) != ',' {
			break
		}
		p.at += 1
	}
	expect(p, ')') or_return
	switch strings.to_upper(name, context.temp_allocator) {
	case "SUM":
		return acc.sum, true
	case "AVG":
		return acc.sum / f64(acc.n), acc.n > 0
	case "MIN":
		return acc.lo, acc.n > 0
	case "MAX":
		return acc.hi, acc.n > 0
	}
	return 0, false
}

// Tally is what the functions are made from: the count, sum and extremes
// of the numbers in their arguments.
Tally :: struct {
	n:      int,
	sum:    f64,
	lo, hi: f64,
}

// fold_arg folds one argument into acc: an expression, or a range, whose
// empty cells are skipped.
fold_arg :: proc(p: ^Parser, acc: ^Tally) -> bool {
	save := p.at
	if from, to, ok := range_ref(p); ok {
		for r in min(from.row, to.row) ..= max(from.row, to.row) {
			for c in min(from.col, to.col) ..= max(from.col, to.col) {
				v := eval_cell(p.sheet, {c, r})
				switch v.kind {
				case .Empty:
				case .Number:
					fold(acc, v.num)
				case .Text, .Error:
					return false
				}
			}
		}
		return true
	}
	p.at = save
	v := expr(p) or_return
	fold(acc, v)
	return true
}

fold :: proc(acc: ^Tally, v: f64) {
	acc.n += 1
	acc.sum += v
	acc.lo = min(acc.lo, v)
	acc.hi = max(acc.hi, v)
}

range_ref :: proc(p: ^Parser) -> (from, to: Cell, ok: bool) {
	from = parse_cell(word(p)) or_return
	expect(p, ':') or_return
	to = parse_cell(word(p)) or_return
	return from, to, true
}

word :: proc(p: ^Parser) -> string {
	skip_space(p)
	start := p.at
	for p.at < len(p.src) && (is_letter(p.src[p.at]) || is_digit(p.src[p.at])) {
		p.at += 1
	}
	return p.src[start:p.at]
}

// number_at is the number in cell c: an empty cell is 0, and text or an
// error is an error.
number_at :: proc(s: ^Sheet, c: Cell) -> (f64, bool) {
	v := eval_cell(s, c)
	switch v.kind {
	case .Empty:
		return 0, true
	case .Number:
		return v.num, true
	case .Text, .Error:
	}
	return 0, false
}

number :: proc(p: ^Parser) -> (v: f64, ok: bool) {
	start := p.at
	for p.at < len(p.src) && (is_digit(p.src[p.at]) || p.src[p.at] == '.') {
		p.at += 1
	}
	return strconv.parse_f64(p.src[start:p.at])
}

// parse_cell reads a reference: a column letter A to Z, either case, then
// a row 0 to 99.
parse_cell :: proc(s: string) -> (c: Cell, ok: bool) {
	if len(s) < 2 || !is_letter(s[0]) {
		return
	}
	row := strconv.parse_int(s[1:], 10) or_return
	col := int((s[0] | 0x20) - 'a') // | 0x20 lower-cases a letter
	if col < 0 || col >= COLS || row < 0 || row >= ROWS {
		return
	}
	return {col, row}, true
}

cell_name :: proc(c: Cell) -> string {
	return fmt.tprintf("%c%d", 'A' + c.col, c.row)
}

peek :: proc(p: ^Parser) -> u8 {
	skip_space(p)
	return p.at < len(p.src) ? p.src[p.at] : 0
}

expect :: proc(p: ^Parser, ch: u8) -> bool {
	if peek(p) != ch {
		return false
	}
	p.at += 1
	return true
}

skip_space :: proc(p: ^Parser) {
	for p.at < len(p.src) && (p.src[p.at] == ' ' || p.src[p.at] == '\t') {
		p.at += 1
	}
}

is_digit :: proc(ch: u8) -> bool {
	return ch >= '0' && ch <= '9'
}

is_letter :: proc(ch: u8) -> bool {
	lower := ch | 0x20
	return lower >= 'a' && lower <= 'z'
}
