package pq

import "core:math"
import "core:testing"

// Every Value is sent as the text its type reads, and comes back through
// read_exact as the same value, at the edges of each type too.
@(test)
values_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)

	res, err := exec_values(
		conn,
		`SELECT $1::bool, $2::int2, $3::int4, $4::int8, $5::float4, $6::float8,
			$7::text, $8::bytea, $9::int8 IS NULL, $10::float8, $11::float8`,
		{
			true,
			i16(min(i16)),
			i32(max(i32)),
			i64(min(i64)),
			f32(0.1),
			f64(1e300),
			"it's",
			[]byte{0, 0xff},
			nil,
			math.inf_f64(-1),
			math.nan_f64(),
		},
	)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(res.rows), 1)
	row := res.rows[0]
	read: Error
	testing.expect_value(t, read_exact(row[0], "a", bool, &read), true)
	testing.expect_value(t, read_exact(row[1], "b", i16, &read), min(i16))
	testing.expect_value(t, read_exact(row[2], "c", i32, &read), max(i32))
	testing.expect_value(t, read_exact(row[3], "d", i64, &read), min(i64))
	testing.expect_value(t, read_exact(row[4], "e", f32, &read), f32(0.1))
	testing.expect_value(t, read_exact(row[5], "f", f64, &read), 1e300)
	testing.expect_value(t, read_exact(row[6], "g", string, &read), "it's")
	blob := read_exact(row[7], "h", []byte, &read)
	testing.expect(t, len(blob) == 2 && blob[0] == 0 && blob[1] == 0xff)
	testing.expect_value(t, read_exact(row[8], "i", bool, &read), true)
	testing.expect(t, math.is_inf(read_exact(row[9], "j", f64, &read), -1))
	testing.expect(t, math.is_nan(read_exact(row[10], "k", f64, &read)))
	testing.expect_value(t, read, nil)
}

// A value read as a type it does not hold sets err, and the first such
// value is the one reported.
@(test)
read_exact_refuses_what_does_not_fit :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?]Maybe(string){nil, "x", "70000", `\y00`}
	for cell, i in cases {
		read: Error
		switch i {
		case 0:
			_ = read_exact(cell, "c", string, &read)
		case 1:
			_ = read_exact(cell, "c", bool, &read)
		case 2:
			_ = read_exact(cell, "c", i16, &read)
		case 3:
			_ = read_exact(cell, "c", []byte, &read)
		}
		testing.expectf(t, read != nil, "case %d read without error", i)
	}
	read: Error
	_ = read_exact(nil, "first", i64, &read)
	_ = read_exact("x", "second", i64, &read)
	f, _ := read.(Fault)
	testing.expect_value(t, f.message, `column first holds "NULL", which is not a i64`)
	testing.expect_value(t, read_exact_maybe(nil, "c", i64, &read), nil)
}

// check_statement is what generated code runs at open, so each kind of
// drift it exists to catch is a Fault here.
@(test)
check_statement_finds_drift :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	sql := `SELECT oid AS id, relname AS name FROM pg_class WHERE oid = $1`
	testing.expect_value(t, check_statement(conn, "q", sql, 1, {"id", "name"}), nil)
	drifts := [?]struct {
		params:  int,
		columns: []string,
	}{{2, {"id", "name"}}, {1, {"id"}}, {1, {"id", "title"}}}
	for d in drifts {
		f, failed := check_statement(conn, "q", sql, d.params, d.columns).(Fault)
		testing.expectf(t, failed && f.sqlstate == FEATURE_NOT_SUPPORTED, "%v: %v", d, f)
	}
	f, failed := check_statement(conn, "q", `SELECT gone FROM pg_class`, 0, {"gone"}).(Fault)
	testing.expect(t, failed && f.sqlstate == "42703", f.message)
}
