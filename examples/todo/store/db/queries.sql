-- engine: sqlite

-- name: todo_state :one
-- Whether todo id is done; no row when it does not exist.
-- params: id: i64
SELECT done AS "done: bool" FROM todo WHERE id = @id;

-- name: counts :one
-- How many todos are active and how many done.
SELECT
	COUNT(*) FILTER (WHERE done = 0) AS "active: i64",
	COUNT(*) FILTER (WHERE done = 1) AS "completed: i64"
FROM todo;

-- name: todos :many
-- The todos a filter keeps, by query.Filter's value: 0 all, 1 active,
-- 2 completed.
-- params: filter: i64
SELECT id, title, done AS "done: bool"
FROM todo
WHERE @filter = 0 OR (@filter = 1 AND done = 0) OR (@filter = 2 AND done = 1)
ORDER BY id;

-- name: insert :exec
-- params: title: string
INSERT INTO todo(title) VALUES (@title);

-- name: set_done :exec
-- params: id: i64, done: bool
UPDATE todo SET done = @done WHERE id = @id;

-- name: set_all :exec
-- Touches only the rows that differ, so the change batch names only those.
-- params: done: bool
UPDATE todo SET done = @done WHERE done != @done;

-- name: set_title :exec
-- params: id: i64, title: string
UPDATE todo SET title = @title WHERE id = @id;

-- name: remove :exec
-- params: id: i64
DELETE FROM todo WHERE id = @id;

-- name: remove_done :exec
DELETE FROM todo WHERE done = 1;
