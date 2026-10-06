-- engine: sqlite

CREATE TABLE note(
	id INTEGER PRIMARY KEY,
	body TEXT NOT NULL,
	pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
	score REAL NOT NULL DEFAULT 0,
	attachment BLOB
) STRICT;

CREATE TABLE label(
	note_id INTEGER NOT NULL REFERENCES note(id),
	name TEXT NOT NULL,
	PRIMARY KEY (note_id, name)
) STRICT, WITHOUT ROWID;
