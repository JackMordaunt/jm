package files_store

import "core:path/filepath"
import "core:testing"

import "jm:sqlite3"

@(private = "file")
Seen :: struct {
	batches: int,
}

@(private = "file")
count :: proc(user: rawptr, batch: Change_Batch) {
	(^Seen)(user).batches += 1
}

@(private = "file")
S :: filepath.SEPARATOR_STRING

@(test)
visits_list_newest_first_once_each :: proc(t: ^testing.T) {
	seen: Seen
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, count, &seen))
	defer close(&st)
	testing.expect(t, visit(&st, "/a", "a", true) == nil)
	testing.expect(t, visit(&st, "/b/file.txt", "file.txt", false) == nil)
	testing.expect(t, visit(&st, "/a", "a", true) == nil)
	items, err := recent(&st)
	testing.expect(t, err == nil)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].path, "/a")
	testing.expect(t, items[0].dir)
	testing.expect_value(t, items[1].name, "file.txt")
	testing.expect(t, seen.batches >= 3, "every committed visit was reported")
}

@(test)
pins_keep_their_order_and_unpin :: proc(t: ^testing.T) {
	seen: Seen
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, count, &seen))
	defer close(&st)
	testing.expect(t, pin(&st, "/work", "work") == nil)
	testing.expect(t, pin(&st, "/play", "play") == nil)
	testing.expect(t, pin(&st, "/work", "work") == nil) // again: ignored
	items, _ := pins(&st)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[0].name, "work")
	testing.expect_value(t, items[1].name, "play")
	testing.expect(t, unpin(&st, "/work") == nil)
	items, _ = pins(&st)
	testing.expect_value(t, len(items), 1)
	testing.expect_value(t, items[0].name, "play")
}

@(test)
places_follow_a_rename_and_go_with_a_trash :: proc(t: ^testing.T) {
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, nil, nil))
	defer close(&st)
	a :: S + "work"
	inner :: a + S + "deep"
	other :: S + "workshop" // shares a prefix, but is not under a
	testing.expect(t, pin(&st, a, "work") == nil)
	testing.expect(t, pin(&st, inner, "deep") == nil)
	testing.expect(t, pin(&st, other, "workshop") == nil)
	testing.expect(t, visit(&st, inner, "deep", true) == nil)
	under, _ := places_under(&st, a)
	testing.expect(t, under)
	none, _ := places_under(&st, S + "elsewhere")
	testing.expect(t, !none)

	b :: S + "jobs"
	testing.expect(t, move_places(&st, a, b) == nil)
	items, _ := pins(&st)
	testing.expect_value(t, len(items), 3)
	testing.expect_value(t, items[0].path, b)
	testing.expect_value(t, items[0].name, "jobs") // renamed itself, so it takes the new name
	testing.expect_value(t, items[1].path, b + S + "deep")
	testing.expect_value(t, items[1].name, "deep")
	testing.expect_value(t, items[2].path, other)
	visited, _ := recent(&st)
	testing.expect_value(t, visited[0].path, b + S + "deep")

	testing.expect(t, forget_places(&st, b) == nil)
	items, _ = pins(&st)
	testing.expect_value(t, len(items), 1)
	testing.expect_value(t, items[0].path, other)
	visited, _ = recent(&st)
	testing.expect_value(t, len(visited), 0)
}

@(test)
the_journal_hands_back_its_newest_change :: proc(t: ^testing.T) {
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, nil, nil))
	defer close(&st)
	_, has, _ := newest(&st)
	testing.expect(t, !has)
	testing.expect(t, journal(&st, 0, "/a", "/b", "") == nil)
	testing.expect(t, journal(&st, 2, "/c", "/T/c", "") == nil)
	row, ok, err := newest(&st)
	testing.expect(t, ok && err == nil)
	testing.expect_value(t, row.change, u8(2))
	testing.expect_value(t, row.b, "/T/c")
	testing.expect(t, unjournal(&st, row.id) == nil)
	row, ok, _ = newest(&st)
	testing.expect(t, ok)
	testing.expect_value(t, row.a, "/a")
	for _ in 0 ..< JOURNAL_KEPT + 5 {
		_ = journal(&st, 1, "/x", "", "")
	}
	rows, _ := sqlite3.query(st.db, "SELECT COUNT(*) FROM journal", allocator = context.temp_allocator)
	testing.expect(t, sqlite3.next(&rows))
	testing.expect_value(t, sqlite3.integer(rows, 0), i64(JOURNAL_KEPT))
	sqlite3.finish(&rows)
}

@(test)
a_rolled_back_transaction_keeps_nothing :: proc(t: ^testing.T) {
	seen: Seen
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, count, &seen))
	defer close(&st)
	testing.expect(t, begin(&st) == nil)
	testing.expect(t, pin(&st, "/a", "a") == nil)
	rollback(&st)
	items, _ := pins(&st)
	testing.expect_value(t, len(items), 0)
	testing.expect_value(t, seen.batches, 0)
}
