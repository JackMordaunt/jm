-- engine: postgres

CREATE TYPE mood AS ENUM ('calm', 'busy', 'done');
CREATE DOMAIN short_text AS text CHECK (length(VALUE) <= 40);

CREATE TABLE note(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	body short_text NOT NULL,
	pinned boolean NOT NULL DEFAULT false,
	rank int4 NOT NULL DEFAULT 0,
	score float8 NOT NULL DEFAULT 0,
	price numeric(12, 2),
	uid uuid NOT NULL DEFAULT gen_random_uuid(),
	at timestamptz NOT NULL DEFAULT now(),
	mood mood NOT NULL DEFAULT 'calm',
	attachment bytea
);

CREATE TABLE label(
	note_id bigint NOT NULL REFERENCES note(id),
	name text NOT NULL,
	PRIMARY KEY (note_id, name)
);
