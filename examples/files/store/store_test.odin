package files_store

import "core:encoding/cbor"
import "core:testing"

import "jm:sqlite3"

import "../shapes"

@(private = "file")
Seen :: struct {
	batches: int,
}

@(private = "file")
count :: proc(user: rawptr, batch: Change_Batch) {
	(^Seen)(user).batches += 1
}

@(private = "file")
recent_of :: proc(t: ^testing.T, st: ^Store) -> shapes.Recent_Result {
	out := apply(st, Query{key = 1, kind = .Recent})
	testing.expect_value(t, len(out), 1)
	r := out[0]
	defer result_free(st, r)
	res: shapes.Recent_Result
	testing.expect(t, cbor.unmarshal_from_bytes(r.data, &res, allocator = context.temp_allocator) == nil)
	return res
}

@(test)
visits_list_newest_first_once_each :: proc(t: ^testing.T) {
	seen: Seen
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, count, &seen))
	defer close(&st)
	apply(&st, Write{op = .Visited, path = text_make("/a"), name = text_make("a"), dir = true})
	apply(&st, Write{op = .Visited, path = text_make("/b/file.txt"), name = text_make("file.txt")})
	apply(&st, Write{op = .Visited, path = text_make("/a"), name = text_make("a"), dir = true})
	res := recent_of(t, &st)
	testing.expect_value(t, len(res.items), 2)
	testing.expect_value(t, res.items[0].path, "/a")
	testing.expect(t, res.items[0].dir)
	testing.expect_value(t, res.items[1].name, "file.txt")
	testing.expect(t, seen.batches >= 3, "every committed visit was reported")
}

@(test)
pins_keep_their_order_and_unpin :: proc(t: ^testing.T) {
	seen: Seen
	st: Store
	testing.expect(t, open(&st, sqlite3.MEMORY, count, &seen))
	defer close(&st)
	apply(&st, Write{op = .Pin, path = text_make("/work"), name = text_make("work")})
	apply(&st, Write{op = .Pin, path = text_make("/play"), name = text_make("play")})
	apply(&st, Write{op = .Pin, path = text_make("/work"), name = text_make("work")}) // again: ignored
	out := apply(&st, Query{key = 2, kind = .Pins})
	r := out[0]
	defer result_free(&st, r)
	res: shapes.Pins_Result
	testing.expect(t, cbor.unmarshal_from_bytes(r.data, &res, allocator = context.temp_allocator) == nil)
	testing.expect_value(t, len(res.items), 2)
	testing.expect_value(t, res.items[0].name, "work")
	testing.expect_value(t, res.items[1].name, "play")
	apply(&st, Write{op = .Unpin, path = text_make("/work")})
	out = apply(&st, Query{key = 2, kind = .Pins})
	r2 := out[0]
	defer result_free(&st, r2)
	res2: shapes.Pins_Result
	testing.expect(t, cbor.unmarshal_from_bytes(r2.data, &res2, allocator = context.temp_allocator) == nil)
	testing.expect_value(t, len(res2.items), 1)
	testing.expect_value(t, res2.items[0].name, "play")
}
