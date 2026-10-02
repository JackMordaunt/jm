package todo_store

import "core:encoding/cbor"
import "core:testing"

import "jm:sqlite3"

import "../logic"
import "../shapes"

@(private = "file")
Seen :: struct {
	batches: [dynamic]Change_Batch,
}

@(private = "file")
record :: proc(user: rawptr, batch: Change_Batch) {
	append(&(^Seen)(user).batches, batch)
}

@(private = "file")
todos_of :: proc(t: ^testing.T, r: Result) -> (res: shapes.Todos_Result) {
	testing.expect(t, cbor.unmarshal_from_bytes(r.data, &res, allocator = context.temp_allocator) == nil)
	return
}

@(test)
writes_change_rows_and_queries_answer_under_their_key :: proc(t: ^testing.T) {
	seen: Seen
	defer delete(seen.batches)
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, record, &seen))
	defer close(&st)

	// Two inserts: a commit each in autocommit mode, one row each.
	apply(&st, logic.Write{op = .Insert, title = logic.text_make("milk")})
	apply(&st, logic.Write{op = .Insert, title = logic.text_make("eggs")})
	testing.expect_value(t, len(seen.batches), 2)
	testing.expect_value(t, seen.batches[1].count, 1)
	testing.expect_value(t, seen.batches[1].rows[0].op, sqlite3.Update_Op.Insert)
	testing.expect_value(t, seen.batches[1].rows[0].rowid, i64(2))

	// A query answers under the key it was asked with, with the counts.
	out := apply(&st, Query{key = 42, filter = .All})
	testing.expect_value(t, len(out), 1)
	// The slice is the store's until the next apply; the result is ours.
	first := out[0]
	defer result_free(&st, first)
	testing.expect(t, first.key == 42)
	res := todos_of(t, first)
	testing.expect_value(t, len(res.items), 2)
	testing.expect_value(t, res.items[1].title, "eggs")
	testing.expect_value(t, res.active, 2)
	testing.expect_value(t, res.completed, 0)

	// Toggling flips the row; the batch names it as an update.
	apply(&st, logic.Write{op = .Set_Done, id = 1})
	testing.expect_value(t, seen.batches[2].rows[0].op, sqlite3.Update_Op.Update)
	done_r := apply(&st, Query{key = 1, filter = .Completed})[0]
	defer result_free(&st, done_r)
	done := todos_of(t, done_r)
	testing.expect_value(t, len(done.items), 1)
	testing.expect(t, done.items[0].done)
	testing.expect_value(t, done.active, 1)
	testing.expect_value(t, done.completed, 1)

	// Set_All touches only the rows that differ: one row, one batch.
	apply(&st, logic.Write{op = .Set_All, done = true})
	testing.expect_value(t, len(seen.batches), 4)
	testing.expect_value(t, seen.batches[3].count, 1)
	testing.expect_value(t, seen.batches[3].rows[0].rowid, i64(2))

	// Remove_Done deletes both in one statement: one batch of two deletes.
	apply(&st, logic.Write{op = .Remove_Done})
	testing.expect_value(t, seen.batches[4].count, 2)
	testing.expect_value(t, seen.batches[4].rows[0].op, sqlite3.Update_Op.Delete)
	last := apply(&st, Query{key = 1, filter = .All})[0]
	defer result_free(&st, last)
	empty := todos_of(t, last)
	testing.expect_value(t, len(empty.items), 0)
}

@(test)
a_rolled_back_transaction_reports_nothing :: proc(t: ^testing.T) {
	seen: Seen
	defer delete(seen.batches)
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, record, &seen))
	defer close(&st)
	testing.expect(t, sqlite3.exec(st.db, "BEGIN") == nil)
	apply(&st, logic.Write{op = .Insert, title = logic.text_make("never")})
	testing.expect_value(t, st.batch.count, 1)
	testing.expect(t, sqlite3.exec(st.db, "ROLLBACK") == nil)
	testing.expect_value(t, st.batch.count, 0)
	testing.expect_value(t, len(seen.batches), 0)
	// A transaction that commits reports once, with every row.
	testing.expect(t, sqlite3.exec(st.db, "BEGIN") == nil)
	apply(&st, logic.Write{op = .Insert, title = logic.text_make("a")})
	apply(&st, logic.Write{op = .Insert, title = logic.text_make("b")})
	testing.expect_value(t, len(seen.batches), 0)
	testing.expect(t, sqlite3.exec(st.db, "COMMIT") == nil)
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
	testing.expect(t, sqlite3.exec(st.db, "BEGIN") == nil)
	for _ in 0 ..< MAX_CHANGES + 3 {
		apply(&st, logic.Write{op = .Insert, title = logic.text_make("x")})
	}
	testing.expect(t, sqlite3.exec(st.db, "COMMIT") == nil)
	testing.expect_value(t, len(seen.batches), 1)
	testing.expect_value(t, seen.batches[0].count, MAX_CHANGES)
	testing.expect(t, seen.batches[0].truncated)
}
