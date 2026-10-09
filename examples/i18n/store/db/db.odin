/*
Package i18n_db is the settings store's SQL: schema.sql creates the table,
and the procs in queries_gen.odin are generated from queries.sql by
tools/jm-sqlgen (`just sqlgen examples/i18n/store/db`), typed by SQLite
itself. Edit the SQL and regenerate; the generated files say so if they fall
behind.
*/
package i18n_db

// SCHEMA creates the table if it is missing. It is safe to run on every open.
SCHEMA :: #load("schema.sql", string)
