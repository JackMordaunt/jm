package notes_queries

import "core:mem"
import "core:testing"

import "jm:sqlite3"

// A read that fails halfway frees what it read: the rows before the failure
// and the partial row it stopped on. The tables here are untyped on purpose,
// so the second note can hold an integer body that the generated reader
// refuses. Its label is read after the body fails, so the partial row owns
// text that only labelled_next can free.
@(test)
a_failed_read_frees_what_it_read :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	tracked := mem.tracking_allocator(&track)

	db, err := sqlite3.open(sqlite3.MEMORY, allocator = context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer sqlite3.close(&db)
	testing.expect_value(
		t,
		sqlite3.exec(
			db,
			`CREATE TABLE note(id INTEGER PRIMARY KEY, body, pinned, score, attachment);
			CREATE TABLE label(note_id, name);
			INSERT INTO note(id, body) VALUES (1, 'first'), (2, 42);
			INSERT INTO label VALUES (1, 'kept'), (2, 'read after the failure');`,
		),
		nil,
	)

	all, aerr := labelled_all(db, tracked)
	f, failed := aerr.(sqlite3.Fault)
	testing.expect(t, failed && f.code == .Mismatch, "the integer body stops the read")
	testing.expect_value(t, len(all), 0)
	delete(f.text, tracked)
	left := len(track.allocation_map)
	testing.expectf(t, left == 0, "%d allocations left", left)

	rows: Labelled_Rows
	read := 0
	if labelled(&rows, db, tracked) {
		for row in labelled_next(&rows) {
			testing.expect_value(t, row.body, "first")
			labelled_free_row(row, tracked)
			read += 1
		}
	}
	testing.expect_value(t, read, 1)
	f, failed = rows.err.(sqlite3.Fault)
	testing.expect(t, failed && f.code == .Mismatch, "the guard keeps the failure in rows.err")
	delete(f.text, tracked)
	left = len(track.allocation_map)
	testing.expectf(t, left == 0, "%d allocations left", left)
}
