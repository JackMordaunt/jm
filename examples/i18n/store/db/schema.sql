-- engine: sqlite

CREATE TABLE IF NOT EXISTS setting(
	name TEXT PRIMARY KEY,
	value TEXT NOT NULL
) STRICT;
