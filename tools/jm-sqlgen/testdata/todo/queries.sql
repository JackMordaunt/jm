-- engine: sqlite

-- name: todo_state :one
-- Whether todo id exists, and whether it is done.
-- params: id: i64
SELECT done AS "done: bool" FROM todo WHERE id = @id;

-- name: counts :one
-- How many todos are active and how many done.
SELECT
	COUNT(*) FILTER (WHERE done = 0) AS "active: i64",
	COUNT(*) FILTER (WHERE done = 1) AS "completed: i64"
FROM todo;

-- name: todos :many
-- The todos a filter shows: 0 all, 1 active, 2 completed.
-- params: filter: i64
SELECT id, title, done AS "done: bool", note
FROM todo
WHERE @filter = 0 OR (@filter = 1 AND done = 0) OR (@filter = 2 AND done = 1)
ORDER BY id;

-- name: tagged :many
-- Each todo with its tags, untagged ones once with no tag.
SELECT t.id, t.title, g.name AS tag
FROM todo t LEFT JOIN tag g ON g.todo_id = t.id
ORDER BY t.id, g.name;

-- name: insert :last_id
-- params: title: string, note: Maybe(string)
INSERT INTO todo(title, note) VALUES (@title, @note);

-- name: set_done :exec
-- params: id: i64, done: bool
UPDATE todo SET done = @done WHERE id = @id;

-- name: set_all :rows
-- Touches only the rows that differ, so the change batch names only those.
-- params: done: bool
UPDATE todo SET done = @done WHERE done != @done;

-- name: tag :exec
-- params: todo_id: i64, name: string
INSERT INTO tag(todo_id, name) VALUES (@todo_id, @name) ON CONFLICT DO NOTHING;

-- name: remove_done :rows
DELETE FROM todo WHERE done = 1;
