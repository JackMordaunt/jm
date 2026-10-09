-- engine: sqlite

-- name: setting :one
-- The value saved under name; no row when none is.
-- params: name: string
SELECT value FROM setting WHERE name = @name;

-- name: set_setting :exec
-- Saves value under name, replacing what was there.
-- params: name: string, value: string
INSERT INTO setting(name, value) VALUES (@name, @value)
ON CONFLICT(name) DO UPDATE SET value = excluded.value;
