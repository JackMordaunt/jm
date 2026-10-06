package notes_pg_queries

import "core:log"
import "core:mem"
import "core:testing"

import "jm:pq"
import "jm:pq/testdb"

// A read that fails halfway frees what it read: the rows before the failure,
// the partial row it stopped on, and the result. The tables here are made
// for the test, in a transaction it rolls back: note.id is text, so the
// second note's id is not an i64, and its body and label, read after it,
// are text that only labelled_next can free.
@(test)
a_failed_read_frees_what_it_read :: proc(t: ^testing.T) {
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to test against: %s", why)
		return
	}
	db, err := pq.connect(allocator = context.temp_allocator)
	if !testing.expect_value(t, err, nil) {
		return
	}
	defer pq.close(db)
	_, err = pq.exec(
		db,
		`BEGIN;
		CREATE TABLE note(id text, body text);
		CREATE TABLE label(note_id text, name text);
		INSERT INTO note VALUES ('1', 'first'), ('x', 'second');
		INSERT INTO label VALUES ('1', 'kept'), ('x', 'read after the failure');`,
		allocator = context.temp_allocator,
	)
	testing.expect_value(t, err, nil)
	defer pq.exec(db, "ROLLBACK", allocator = context.temp_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	tracked := mem.tracking_allocator(&track)

	all, aerr := labelled_all(db, tracked)
	f, failed := aerr.(pq.Fault)
	testing.expect(t, failed && f.sqlstate == "", "the text id stops the read")
	testing.expect_value(t, len(all), 0)
	delete(f.message, tracked)
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
	f, failed = rows.err.(pq.Fault)
	testing.expect(t, failed, "the guard keeps the failure in rows.err")
	delete(f.message, tracked)
	left = len(track.allocation_map)
	testing.expectf(t, left == 0, "%d allocations left", left)
}
