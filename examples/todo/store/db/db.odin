/*
Package todo_db is the todo store's SQL: schema.sql creates the table, and
the procs in queries_gen.odin are generated from queries.sql by
tools/jm-sqlgen (`just sqlgen examples/todo/store/db`), typed by SQLite
itself. Edit the SQL and regenerate; the generated files say so if they fall
behind.
*/
package todo_db

// SCHEMA creates the table if it is missing. It is safe to run on every open.
SCHEMA :: #load("schema.sql", string)
