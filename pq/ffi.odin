/*
The raw C API: the subset of libpq-fe.h the wrapper needs, under the C names,
exported so a caller that needs an interface the wrapper does not cover can
reach for it. The wrapper in pq.odin is what scripts should use. The
declarations were taken from the PostgreSQL 18.6 header and use nothing newer
than 9.x. The soname has been libpq.so.5 since PostgreSQL 8.2, December
2006, and a soname bump is how libpq would announce a broken ABI.

Unlike every other C library in this collection, libpq is not vendored. It is
linked dynamically from the system, and the package doc in pq.odin says why.
`foreign import` names the system library rather than an archive under this
directory, and `odin check` never opens it — measured with odin dev-2026-09
for all three targets on a machine where nothing was built — so `just check` type-checks all
three targets on a machine with no libpq installed. Only `odin build` and
`odin test` need it.
*/
package pq

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "system:libpq.lib"
} else {
	foreign import lib "system:pq"
}

// PGconn is one connection to a server. libpq owns the memory; PQfinish
// releases it, and every string read off the connection with it.
PGconn :: struct {}

// PGresult is the outcome of one command. libpq owns the memory; PQclear
// releases it, and every string read out of the result with it.
PGresult :: struct {}

// Oid is a PostgreSQL object identifier, as PQexecParams takes parameter types.
Oid :: c.uint

// ConnStatusType is PQstatus. Only the first two can be seen through the
// blocking PQconnectdb; the rest are states of a non-blocking connect.
ConnStatusType :: enum c.int {
	CONNECTION_OK,
	CONNECTION_BAD,
	CONNECTION_STARTED,
	CONNECTION_MADE,
	CONNECTION_AWAITING_RESPONSE,
	CONNECTION_AUTH_OK,
	CONNECTION_SETENV,
	CONNECTION_SSL_STARTUP,
	CONNECTION_NEEDED,
	CONNECTION_CHECK_WRITABLE,
	CONNECTION_CONSUME,
	CONNECTION_GSS_STARTUP,
	CONNECTION_CHECK_TARGET,
	CONNECTION_CHECK_STANDBY,
	CONNECTION_ALLOCATED,
	CONNECTION_AUTHENTICATING,
}

// ExecStatusType is PQresultStatus.
ExecStatusType :: enum c.int {
	PGRES_EMPTY_QUERY = 0,
	PGRES_COMMAND_OK,
	PGRES_TUPLES_OK,
	PGRES_COPY_OUT,
	PGRES_COPY_IN,
	PGRES_BAD_RESPONSE,
	PGRES_NONFATAL_ERROR,
	PGRES_FATAL_ERROR,
	PGRES_COPY_BOTH,
	PGRES_SINGLE_TUPLE,
	PGRES_PIPELINE_SYNC,
	PGRES_PIPELINE_ABORTED,
	PGRES_TUPLES_CHUNK,
}

// PGTransactionStatusType is PQtransactionStatus.
PGTransactionStatusType :: enum c.int {
	PQTRANS_IDLE,
	PQTRANS_ACTIVE,
	PQTRANS_INTRANS,
	PQTRANS_INERROR,
	PQTRANS_UNKNOWN,
}

// Field codes for PQresultErrorField, from postgres_ext.h. Each names one
// part of an error or notice as the server sent it.
PG_DIAG_SQLSTATE :: 'C'
PG_DIAG_MESSAGE_PRIMARY :: 'M'
PG_DIAG_MESSAGE_DETAIL :: 'D'
PG_DIAG_MESSAGE_HINT :: 'H'
// A 1-based index into the statement, counted in characters, not bytes:
// the protocol documentation's "Error and Notice Message Fields" says so,
// and error_carries_sqlstate_and_position in the tests pins it.
PG_DIAG_STATEMENT_POSITION :: 'P'

// PQnoticeProcessor receives each NOTICE or WARNING the server sends, already
// formatted, with a trailing newline. The default one prints to stderr.
PQnoticeProcessor :: #type proc "c" (arg: rawptr, message: cstring)

@(default_calling_convention = "c")
foreign lib {
	PQconnectdb       :: proc(conninfo: cstring) -> ^PGconn ---
	PQconnectdbParams :: proc(keywords: [^]cstring, values: [^]cstring, expand_dbname: c.int) -> ^PGconn ---
	PQstatus          :: proc(conn: ^PGconn) -> ConnStatusType ---
	PQerrorMessage    :: proc(conn: ^PGconn) -> cstring ---
	PQfinish          :: proc(conn: ^PGconn) ---

	PQexec               :: proc(conn: ^PGconn, query: cstring) -> ^PGresult ---
	PQexecParams         :: proc(conn: ^PGconn, command: cstring, nParams: c.int, paramTypes: [^]Oid, paramValues: [^]cstring, paramLengths: [^]c.int, paramFormats: [^]c.int, resultFormat: c.int) -> ^PGresult ---
	PQresultStatus       :: proc(res: ^PGresult) -> ExecStatusType ---
	PQresultErrorMessage :: proc(res: ^PGresult) -> cstring ---
	PQresultErrorField   :: proc(res: ^PGresult, fieldcode: c.int) -> cstring ---

	// An empty stmtName is the unnamed statement, which the next Parse or
	// simple query replaces, so describing through it leaves nothing behind.
	PQprepare          :: proc(
		conn: ^PGconn,
		stmtName: cstring,
		query: cstring,
		nParams: c.int,
		paramTypes: [^]Oid,
	) -> ^PGresult ---
	PQdescribePrepared :: proc(conn: ^PGconn, stmtName: cstring) -> ^PGresult ---
	PQnparams          :: proc(res: ^PGresult) -> c.int ---
	PQparamtype        :: proc(res: ^PGresult, param_num: c.int) -> Oid ---

	PQntuples   :: proc(res: ^PGresult) -> c.int ---
	PQnfields   :: proc(res: ^PGresult) -> c.int ---
	PQfname     :: proc(res: ^PGresult, field_num: c.int) -> cstring ---
	PQfnumber   :: proc(res: ^PGresult, field_name: cstring) -> c.int ---
	PQftype     :: proc(res: ^PGresult, field_num: c.int) -> Oid ---
	PQfmod      :: proc(res: ^PGresult, field_num: c.int) -> c.int ---
	PQftable    :: proc(res: ^PGresult, field_num: c.int) -> Oid ---
	PQftablecol :: proc(res: ^PGresult, field_num: c.int) -> c.int ---
	PQgetvalue  :: proc(res: ^PGresult, tup_num: c.int, field_num: c.int) -> [^]u8 ---
	PQgetisnull :: proc(res: ^PGresult, tup_num: c.int, field_num: c.int) -> c.int ---
	PQgetlength :: proc(res: ^PGresult, tup_num: c.int, field_num: c.int) -> c.int ---
	PQcmdTuples :: proc(res: ^PGresult) -> cstring ---
	PQclear     :: proc(res: ^PGresult) ---

	PQescapeLiteral    :: proc(conn: ^PGconn, str: [^]u8, length: c.size_t) -> cstring ---
	PQescapeIdentifier :: proc(conn: ^PGconn, str: [^]u8, length: c.size_t) -> cstring ---
	PQfreemem          :: proc(ptr: rawptr) ---

	PQdb                :: proc(conn: ^PGconn) -> cstring ---
	PQuser              :: proc(conn: ^PGconn) -> cstring ---
	PQhost              :: proc(conn: ^PGconn) -> cstring ---
	PQhostaddr          :: proc(conn: ^PGconn) -> cstring ---
	PQport              :: proc(conn: ^PGconn) -> cstring ---
	PQparameterStatus   :: proc(conn: ^PGconn, paramName: cstring) -> cstring ---
	PQserverVersion     :: proc(conn: ^PGconn) -> c.int ---
	PQtransactionStatus :: proc(conn: ^PGconn) -> PGTransactionStatusType ---

	PQsetNoticeProcessor :: proc(conn: ^PGconn, processor: PQnoticeProcessor, arg: rawptr) -> PQnoticeProcessor ---
}
