-- engine: postgres

-- name: note :one
-- The note with id, if there is one.
SELECT body, pinned, rank, score, price, uid, at, mood, attachment
FROM note WHERE id = @id;

-- name: totals :one
-- How many notes there are, and their summed score, which is NULL when
-- there are none.
SELECT count(*) AS "notes: i64", sum(score) AS score FROM note;

-- name: labelled :many
-- Each note with its labels, an unlabelled one once with no label.
SELECT n.id, n.body, l.name AS label
FROM note n LEFT JOIN label l ON l.note_id = n.id
ORDER BY n.id, l.name;

-- name: by_mood :many
-- Notes counted by mood and rank, with ROLLUP's subtotals.
SELECT mood, rank, count(*) AS "notes: i64"
FROM note GROUP BY ROLLUP (mood, rank);

-- name: add :one
-- params: body: string, attachment: Maybe([]byte)
INSERT INTO note(body, attachment) VALUES (@body, @attachment) RETURNING id;

-- name: rescore :rows
-- params: id: i64, score: f64
UPDATE note SET score = @score, rank = rank + 1 WHERE id = @id;

-- name: label :exec
INSERT INTO label(note_id, name) VALUES (@note_id, @name) ON CONFLICT DO NOTHING;

-- name: unpin_all :rows
UPDATE note SET pinned = false WHERE pinned;
