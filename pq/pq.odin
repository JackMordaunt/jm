/*
Package pq is PostgreSQL for scripts: connect, run a statement, read what came
back, over the system's libpq.

	conn := must(pq.connect()) // PGHOST, PGDATABASE and the rest, as psql reads them
	defer pq.close(conn)

	res, err := pq.exec(conn, `SELECT id, serial_number FROM rig WHERE site = $1`, {"north"})
	if err != nil {
		fault := err.(pq.Fault)
		fmt.eprintfln("%s: %s", fault.sqlstate, fault.message)
		return
	}
	defer pq.destroy(&res)
	for row in res.rows {
		serial, present := row[1].?
		fmt.println(row[0].? or_else "NULL", present ? serial : "NULL")
	}

Linking: this is the one C library in the collection that is not vendored.
libpq is linked dynamically, from the system, and a built script needs
libpq.so.5 at runtime. The other bindings vendor their C because it compiles
with a plain `cc` and nothing else; libpq does not. It is a slice of the
PostgreSQL tree with its own configure step, and it drags in OpenSSL and GSSAPI
for TLS and Kerberos, which are libraries a machine should update on its own
schedule rather than have frozen into every script. What makes linking it
reasonable is its record: its soname has been libpq.so.5 since PostgreSQL 8.2
in December 2006, and every
machine with a PostgreSQL client — psql included — already has it. `odin check`
never opens a foreign import, so `just check` still type-checks all three
targets on a machine without libpq; only building or testing needs it. Built
and tested on Linux against libpq 18.6. Windows links libpq.lib and is
untested, like every other Windows build here.

Connecting: `connect("")` hands libpq no parameters of its own, so it reads
PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD, PGOPTIONS and the rest from the
environment, and ~/.pgpass, exactly as psql does. A conninfo string
(`host=db dbname=app`) or a URL (`postgresql://app@db/app`) works too, and what
it names overrides the environment. The one parameter this package adds is
client_encoding=UTF8, because an Odin string is UTF-8; a conninfo that names
its own client_encoding wins over it.

Nothing here returns the password. `identity` reports host, port, database,
user and server version — what a caller needs to check it reached the database
it meant to — and deliberately not PQpass.

Values: every parameter is sent and every column read as text, the way psql
shows them: a caller that wants a number parses it. A column is a
Maybe(string), because NULL and the empty string are different values and a
string alone cannot tell them apart. Parameters are sent separately from the
statement, never interpolated into it; `escape_literal` and
`escape_identifier` are for the places SQL does not take a parameter, such as
a table name.

Errors: a Fault carries the server's SQLSTATE, and that is the field to branch
on — `23505` for a unique violation, `25006` for a write in a read-only
transaction — since the message is translated and reworded between releases.
Its position is where the server says the statement went wrong: 1-based,
counted in characters rather than bytes, as PostgreSQL counts it, and 0 when
the failure has no position. A Fault the binding raised itself, before
anything reached the server, has an empty sqlstate.

NUL: libpq takes every statement, parameter and literal as a NUL-terminated C
string, and an Odin string may hold a NUL in the middle. Handed over as it
stands, everything after the NUL would silently not be sent, and a statement
nobody wrote would run and report success. So every call refuses a NUL, with
the byte offset in the message and, for the statement itself, the position of
the NUL in the same units the server uses.

Memory: every `char *` libpq hands out belongs to something. What comes out of
a result dies at PQclear, what comes off a connection dies at PQfinish, and
what PQescapeLiteral and PQescapeIdentifier return must be released with
PQfreemem rather than any Odin allocator. This package clones all of it into
the allocator the call was given before releasing the original, so nothing it
returns points into libpq and a Result or an Identity outlives the connection.
It is the trap jm:sqlite3's doc comment describes for text columns, in another
dialect; `values_outlive_the_connection` in the tests reads everything after
the connection is closed, and under -sanitize:address a missing clone traps
there.

Notices: a NOTICE or WARNING from the server — `DROP TABLE IF EXISTS` on a
missing table, say — is appended to Conn.notices instead of being printed to
stderr, which is libpq's default and would mix it into a script's own output.

COPY is not supported: a COPY to or from STDOUT or STDIN comes back as a Fault
with SQLSTATE 0A000, feature_not_supported. libpq ends the COPY on the
connection's next exec, so the connection stays usable.

Threads: libpq is thread-safe per connection and not across one. Give each
thread its own Conn — a jm:flow worker owns one in its state slot — or guard a
shared one with a mutex; notices is appended to without a lock.
*/
package pq

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// Fault is a call that failed: the server's own account of it where there is
// one. Every string is cloned, so a Fault outlives the call and the
// connection.
Fault :: struct {
	// The primary message, one line: `relation "rig" does not exist`.
	message:  string,
	// A second line of detail and a suggestion, when the server gave them.
	detail:   string,
	hint:     string,
	// The five-character SQLSTATE: `42P01`, `23505`. Empty when the failure
	// never reached the server — a refused NUL, a connection that failed.
	// COPY is refused with 0A000, because by then it has.
	sqlstate: string,
	// 1-based, in characters, into the statement; 0 when there is none.
	position: int,
}

// Error is nil when a call succeeded, so `or_return` and prelude.must both
// work on it.
Error :: union {
	Fault,
}

// Exec_Status is what a command came back as. exec only ever hands back the
// first three; the rest are libpq's, named here so a caller reaching into
// ffi.odin can read them.
Exec_Status :: enum c.int {
	Empty_Query,
	Command_Ok,
	Tuples_Ok,
	Copy_Out,
	Copy_In,
	Bad_Response,
	Nonfatal_Error,
	Fatal_Error,
	Copy_Both,
	Single_Tuple,
	Pipeline_Sync,
	Pipeline_Aborted,
	Tuples_Chunk,
}

// Transaction_Status is where the connection is between commands. In_Error
// is a transaction that has failed and will refuse everything until it is
// rolled back.
Transaction_Status :: enum c.int {
	Idle,
	Active,
	In_Transaction,
	In_Error,
	Unknown,
}

// Conn is an open connection. One thread at a time.
Conn :: struct {
	raw:       ^PGconn,
	// Where connect put the Conn, and where notices are cloned to.
	allocator: mem.Allocator,
	// Every NOTICE and WARNING the server has sent, oldest first, without
	// the trailing newline. clear_notices empties it.
	notices:   [dynamic]string,
}

// Result is what one command returned, cloned out of libpq.
Result :: struct {
	// Column names, in order. Empty for a command that returns no rows.
	columns:    []string,
	// rows[i][j] is row i's value in column j: a string, or nil for NULL.
	rows:       [][]Maybe(string),
	// How many rows an INSERT, UPDATE, DELETE, MERGE, SELECT, MOVE, FETCH or
	// COPY touched, as the server's command tag says; 0 for anything else.
	cmd_tuples: int,
	status:     Exec_Status,
	allocator:  mem.Allocator,
}

// Identity is which server and database a connection reached, as libpq has
// it after connecting. It never includes the password.
Identity :: struct {
	// The host name, IP address or, for a Unix socket, the socket's
	// directory, and the port as text.
	host:           string,
	port:           string,
	db:             string,
	user:           string,
	// PQserverVersion: 180006 for 18.6, 0 when the connection is gone.
	server_version: int,
}

// connect opens a connection. "" takes every parameter from the environment;
// a conninfo string or a URL overrides it. See the package doc.
connect :: proc(conninfo := "", allocator := context.allocator) -> (conn: ^Conn, err: Error) {
	if i := strings.index_byte(conninfo, 0); i >= 0 {
		return nil, refusal(fmt.tprintf("conninfo holds a NUL byte at offset %d", i), 0, allocator)
	}
	// client_encoding comes first so a conninfo naming its own overrides it:
	// libpq takes the last value it sees for a keyword, and expands dbname
	// into the keywords it holds where dbname stands in the list.
	keywords := [3]cstring{"client_encoding", "dbname", nil}
	values := [3]cstring{"UTF8", nil, nil}
	if conninfo == "" {
		keywords[1] = nil
	} else {
		values[1] = strings.clone_to_cstring(conninfo, context.temp_allocator)
	}
	raw := PQconnectdbParams(&keywords[0], &values[0], 1)
	if raw == nil {
		return nil, refusal("libpq could not allocate a connection", 0, allocator)
	}
	if PQstatus(raw) != .CONNECTION_OK {
		err = Fault {
			message = clone_trimmed(PQerrorMessage(raw), allocator),
		}
		// A failed connection still has to be finished, or it leaks.
		PQfinish(raw)
		return nil, err
	}
	conn = new(Conn, allocator)
	conn.raw = raw
	conn.allocator = allocator
	conn.notices = make([dynamic]string, allocator)
	PQsetNoticeProcessor(raw, on_notice, conn)
	return conn, nil
}

// close ends the connection and frees the Conn. Anything already cloned out
// of it — a Result, an Identity, a Fault — stays valid. nil is ignored.
close :: proc(conn: ^Conn) {
	if conn == nil {
		return
	}
	if conn.raw != nil {
		PQfinish(conn.raw)
	}
	clear_notices(conn)
	delete(conn.notices)
	free(conn, conn.allocator)
}

// exec runs sql and returns what it produced. With no args, sql may hold
// several statements separated by semicolons, run as one implicit
// transaction, and the Result is the last one's — libpq's rule for PQexec.
// With args, sql is exactly one statement and args fill $1, $2 and so on,
// as text the server converts to each parameter's type.
exec :: proc(
	conn: ^Conn,
	sql: string,
	args: []string = {},
	allocator := context.allocator,
) -> (
	result: Result,
	err: Error,
) {
	if conn == nil || conn.raw == nil {
		return {}, refusal("the connection is closed", 0, allocator)
	}
	if i := strings.index_byte(sql, 0); i >= 0 {
		return {}, refusal(
			fmt.tprintf("statement holds a NUL byte at offset %d, which libpq would read as its end", i),
			utf8.rune_count_in_string(sql[:i]) + 1,
			allocator,
		)
	}
	for arg, n in args {
		if i := strings.index_byte(arg, 0); i >= 0 {
			return {}, refusal(
				fmt.tprintf("argument %d holds a NUL byte at offset %d, which libpq would read as its end", n + 1, i),
				0,
				allocator,
			)
		}
	}

	text := strings.clone_to_cstring(sql, context.temp_allocator)
	res: ^PGresult
	if len(args) == 0 {
		res = PQexec(conn.raw, text)
	} else {
		values := make([]cstring, len(args), context.temp_allocator)
		for arg, i in args {
			values[i] = strings.clone_to_cstring(arg, context.temp_allocator)
		}
		// No types, so the server infers each from the statement; no lengths
		// or formats, because text parameters are NUL-terminated; and a
		// result format of 0, text.
		res = PQexecParams(conn.raw, text, c.int(len(args)), nil, raw_data(values), nil, nil, 0)
	}
	if res == nil {
		// PQexec only returns NULL when it could not allocate a result or
		// could not send the command at all; the reason is on the connection.
		return {}, Fault{message = clone_trimmed(PQerrorMessage(conn.raw), allocator)}
	}
	defer PQclear(res)

	status := Exec_Status(PQresultStatus(res))
	#partial switch status {
	case .Empty_Query, .Command_Ok, .Tuples_Ok:
	case .Copy_In, .Copy_Out, .Copy_Both:
		// The server has started the COPY by now, so this is not a refusal
		// that stopped anything being sent, and it carries the code
		// PostgreSQL itself uses for an unsupported feature.
		f := refusal("COPY to or from the client is not supported", 0, allocator)
		f.sqlstate = strings.clone(FEATURE_NOT_SUPPORTED, allocator)
		return {}, f
	case:
		return {}, fault(conn, res, allocator)
	}

	result.status = status
	result.allocator = allocator
	nfields := int(PQnfields(res))
	ntuples := int(PQntuples(res))
	result.columns = make([]string, nfields, allocator)
	for f in 0 ..< nfields {
		result.columns[f] = strings.clone_from_cstring(PQfname(res, c.int(f)), allocator)
	}
	result.rows = make([][]Maybe(string), ntuples, allocator)
	for r in 0 ..< ntuples {
		row := make([]Maybe(string), nfields, allocator)
		for f in 0 ..< nfields {
			if PQgetisnull(res, c.int(r), c.int(f)) != 0 {
				continue
			}
			// Cloned now: the bytes are the result's, and the defer above
			// frees them before the caller sees the row.
			n := int(PQgetlength(res, c.int(r), c.int(f)))
			p := PQgetvalue(res, c.int(r), c.int(f))
			row[f] = strings.clone(string(p[:n]), allocator)
		}
		result.rows[r] = row
	}
	if n, ok := strconv.parse_int(string(PQcmdTuples(res))); ok {
		result.cmd_tuples = n
	}
	return result, nil
}

// destroy frees everything in r and zeroes it. A script on an arena need not
// call it.
destroy :: proc(r: ^Result) {
	if r == nil {
		return
	}
	for name in r.columns {
		delete(name, r.allocator)
	}
	delete(r.columns, r.allocator)
	for row in r.rows {
		for v in row {
			if s, present := v.?; present {
				delete(s, r.allocator)
			}
		}
		delete(row, r.allocator)
	}
	delete(r.rows, r.allocator)
	r^ = {}
}

// escape_literal quotes s as a string literal, quotes included, for the
// places SQL does not take a parameter. Prefer exec's args wherever one
// fits: a parameter is never parsed at all.
escape_literal :: proc(conn: ^Conn, s: string, allocator := context.allocator) -> (string, Error) {
	return escape(conn, s, false, allocator)
}

// escape_identifier quotes s as an identifier — a table, column or schema
// name — double quotes included.
escape_identifier :: proc(conn: ^Conn, s: string, allocator := context.allocator) -> (string, Error) {
	return escape(conn, s, true, allocator)
}

// identity reports which server and database conn reached. The strings are
// cloned into allocator, so they outlive the connection.
identity :: proc(conn: ^Conn, allocator := context.allocator) -> Identity {
	if conn == nil || conn.raw == nil {
		return {}
	}
	return Identity {
		host = clone_trimmed(PQhost(conn.raw), allocator),
		port = clone_trimmed(PQport(conn.raw), allocator),
		db = clone_trimmed(PQdb(conn.raw), allocator),
		user = clone_trimmed(PQuser(conn.raw), allocator),
		server_version = int(PQserverVersion(conn.raw)),
	}
}

// transaction_status is where conn stands between commands: idle, inside a
// transaction, or inside one that has failed.
transaction_status :: proc(conn: ^Conn) -> Transaction_Status {
	if conn == nil || conn.raw == nil {
		return .Unknown
	}
	return Transaction_Status(PQtransactionStatus(conn.raw))
}

// clear_notices frees and forgets every notice conn has collected.
clear_notices :: proc(conn: ^Conn) {
	for n in conn.notices {
		delete(n, conn.allocator)
	}
	clear(&conn.notices)
}

// FEATURE_NOT_SUPPORTED is SQLSTATE 0A000, what exec reports for COPY.
FEATURE_NOT_SUPPORTED :: "0A000"

// empty_byte backs the pointer handed to libpq for an empty string, so it
// sees a valid address with length 0 rather than NULL.
@(private)
empty_byte: u8

@(private)
escape :: proc(conn: ^Conn, s: string, identifier: bool, allocator: mem.Allocator) -> (string, Error) {
	if conn == nil || conn.raw == nil {
		return "", refusal("the connection is closed", 0, allocator)
	}
	// libpq stops escaping at a NUL and says nothing, so a literal would
	// quietly lose its tail.
	if i := strings.index_byte(s, 0); i >= 0 {
		return "", refusal(
			fmt.tprintf("text holds a NUL byte at offset %d, which libpq would read as its end", i),
			0,
			allocator,
		)
	}
	p := len(s) > 0 ? raw_data(s) : ([^]u8)(&empty_byte)
	quoted := identifier ? PQescapeIdentifier(conn.raw, p, c.size_t(len(s))) : PQescapeLiteral(conn.raw, p, c.size_t(len(s)))
	if quoted == nil {
		// Text that is not valid in the client encoding, or no memory.
		return "", Fault{message = clone_trimmed(PQerrorMessage(conn.raw), allocator)}
	}
	// PQfreemem, not the allocator: libpq malloc'd it.
	out := strings.clone_from_cstring(quoted, allocator)
	PQfreemem(rawptr(quoted))
	return out, nil
}

// fault copies a failed result's fields out of libpq before the caller's
// PQclear frees them.
@(private)
fault :: proc(conn: ^Conn, res: ^PGresult, allocator: mem.Allocator) -> Fault {
	field :: proc(res: ^PGresult, code: rune, allocator: mem.Allocator) -> string {
		return clone_trimmed(PQresultErrorField(res, c.int(code)), allocator)
	}
	f := Fault {
		message  = field(res, PG_DIAG_MESSAGE_PRIMARY, allocator),
		detail   = field(res, PG_DIAG_MESSAGE_DETAIL, allocator),
		hint     = field(res, PG_DIAG_MESSAGE_HINT, allocator),
		sqlstate = field(res, PG_DIAG_SQLSTATE, allocator),
	}
	if p := PQresultErrorField(res, c.int(PG_DIAG_STATEMENT_POSITION)); p != nil {
		f.position, _ = strconv.parse_int(string(p))
	}
	// An error libpq raised itself, such as a lost connection, has no
	// fields, only a message.
	if f.message == "" {
		delete(f.message, allocator)
		f.message = clone_trimmed(PQresultErrorMessage(res), allocator)
	}
	if f.message == "" {
		delete(f.message, allocator)
		f.message = clone_trimmed(PQerrorMessage(conn.raw), allocator)
	}
	return f
}

// refusal is a Fault the binding raised before anything reached the server.
@(private)
refusal :: proc(message: string, position: int, allocator: mem.Allocator) -> Fault {
	return Fault{message = strings.clone(message, allocator), position = position}
}

// clone_trimmed copies a C string without its trailing newline, which libpq
// leaves on most of its messages. nil gives "".
@(private)
clone_trimmed :: proc(s: cstring, allocator: mem.Allocator) -> string {
	if s == nil {
		return ""
	}
	return strings.clone(strings.trim_right_space(string(s)), allocator)
}

// on_notice is the notice processor connect installs. libpq calls it on the
// thread running the command, with the Conn it was given.
@(private)
on_notice :: proc "c" (arg: rawptr, message: cstring) {
	conn := (^Conn)(arg)
	context = runtime.default_context()
	append(&conn.notices, clone_trimmed(message, conn.allocator))
}
