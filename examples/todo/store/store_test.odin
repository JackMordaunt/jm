package todo_store

import "core:testing"

import "jm:sqlite3"

import "../../common"

@(private = "file")
Seen :: struct {
	batches: [dynamic]Change_Batch,
}

@(private = "file")
record :: proc(user: rawptr, batch: Change_Batch) {
	append(&(^Seen)(user).batches, batch)
}

@(test)
writes_change_rows_and_reads_see_them :: proc(t: ^testing.T) {
	seen: Seen
	defer delete(seen.batches)
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, record, &seen))
	defer close(&st)

	// Two inserts: a commit each in autocommit mode, one row each.
	testing.expect(t, insert(&st, "milk") == nil)
	testing.expect(t, insert(&st, "eggs") == nil)
	testing.expect_value(t, len(seen.batches), 2)
	testing.expect_value(t, seen.batches[1].count, 1)
	testing.expect_value(t, seen.batches[1].rows[0].op, sqlite3.Update_Op.Insert)
	testing.expect_value(t, seen.batches[1].rows[0].rowid, i64(2))

	res, err := todos(&st, .All)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(res.items), 2)
	testing.expect_value(t, res.items[1].title, "eggs")
	testing.expect_value(t, res.active, 2)
	testing.expect_value(t, res.completed, 0)

	// set_done sets the row; the batch names it as an update.
	testing.expect(t, set_done(&st, 1, true) == nil)
	testing.expect_value(t, seen.batches[2].rows[0].op, sqlite3.Update_Op.Update)
	exists, done, serr := todo_state(&st, 1)
	testing.expect(t, serr == nil && exists && done)
	exists, _, _ = todo_state(&st, 99)
	testing.expect(t, !exists)
	res, _ = todos(&st, .Completed)
	testing.expect_value(t, len(res.items), 1)
	testing.expect(t, res.items[0].done)
	testing.expect_value(t, res.active, 1)
	testing.expect_value(t, res.completed, 1)

	// set_all touches only the rows that differ: one row, one batch.
	testing.expect(t, set_all(&st, true) == nil)
	testing.expect_value(t, len(seen.batches), 4)
	testing.expect_value(t, seen.batches[3].count, 1)
	testing.expect_value(t, seen.batches[3].rows[0].rowid, i64(2))

	// remove_done deletes both in one statement: one batch of two deletes.
	testing.expect(t, remove_done(&st) == nil)
	testing.expect_value(t, seen.batches[4].count, 2)
	testing.expect_value(t, seen.batches[4].rows[0].op, sqlite3.Update_Op.Delete)
	res, _ = todos(&st, .All)
	testing.expect_value(t, len(res.items), 0)
}

@(test)
a_rolled_back_transaction_reports_nothing :: proc(t: ^testing.T) {
	seen: Seen
	defer delete(seen.batches)
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, record, &seen))
	defer close(&st)
	testing.expect(t, begin(&st) == nil)
	testing.expect(t, insert(&st, "never") == nil)
	testing.expect_value(t, st.watcher.batch.count, 1)
	rollback(&st)
	testing.expect_value(t, st.watcher.batch.count, 0)
	testing.expect_value(t, len(seen.batches), 0)
	res, _ := todos(&st, .All)
	testing.expect_value(t, len(res.items), 0)
	// A transaction that commits reports once, with every row.
	testing.expect(t, begin(&st) == nil)
	testing.expect(t, insert(&st, "a") == nil)
	testing.expect(t, insert(&st, "b") == nil)
	testing.expect_value(t, len(seen.batches), 0)
	testing.expect(t, commit(&st) == nil)
	testing.expect_value(t, len(seen.batches), 1)
	testing.expect_value(t, seen.batches[0].count, 2)
}

@(test)
a_batch_past_its_capacity_says_so :: proc(t: ^testing.T) {
	seen: Seen
	defer delete(seen.batches)
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, record, &seen))
	defer close(&st)
	testing.expect(t, begin(&st) == nil)
	for _ in 0 ..< common.MAX_CHANGES + 3 {
		testing.expect(t, insert(&st, "x") == nil)
	}
	testing.expect(t, commit(&st) == nil)
	testing.expect_value(t, len(seen.batches), 1)
	testing.expect_value(t, seen.batches[0].count, common.MAX_CHANGES)
	testing.expect(t, seen.batches[0].truncated)
}
