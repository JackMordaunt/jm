-- engine: sqlite

-- name: note :one
-- The note with id, if there is one.
-- params: id: i64
SELECT body, pinned AS "pinned: bool", score, attachment FROM note WHERE id = @id;

-- name: totals :one
-- How many notes there are and their summed score, which is NULL when
-- there are none.
SELECT count(*) AS "notes: i64", sum(score) AS "score: Maybe(f64)" FROM note;

-- name: labelled :many
-- Each note with its labels, an unlabelled one once with no label.
SELECT n.id, n.body, l.name AS label
FROM note n LEFT JOIN label l ON l.note_id = n.id
ORDER BY n.id, l.name;

-- name: add :last_id
-- params: body: string, attachment: Maybe([]byte)
INSERT INTO note(body, attachment) VALUES (@body, @attachment);

-- name: rescore :rows
-- params: id: i64, score: f64
UPDATE note SET score = @score WHERE id = @id;

-- name: label :exec
-- params: note_id: i64, name: string
INSERT INTO label(note_id, name) VALUES (@note_id, @name) ON CONFLICT DO NOTHING;

-- name: unpin_all :rows
UPDATE note SET pinned = 0 WHERE pinned = 1;
