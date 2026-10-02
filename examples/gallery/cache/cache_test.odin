package gallery_cache

import "core:os"
import "core:path/filepath"
import "core:testing"

@(private = "file")
temp_file :: proc(name: string) -> string {
	dir, _ := os.temp_directory(context.temp_allocator)
	path, _ := filepath.join({dir, name}, context.temp_allocator)
	_ = os.write_entire_file(path, []byte{1, 2, 3})
	return path
}

@(test)
least_recent_goes_first_and_a_get_renews :: proc(t: ^testing.T) {
	c: Cache
	init(&c, 250)
	defer destroy(&c)
	a, b, d := temp_file("cache-a"), temp_file("cache-b"), temp_file("cache-d")
	put(&c, 1, a, 100)
	put(&c, 2, b, 100)
	_, hit := get(&c, 1) // 1 is now the most recent; 2 the least
	testing.expect(t, hit)
	put(&c, 3, d, 100) // 300 > 250: 2 goes
	s := stats(&c)
	testing.expect_value(t, s.entries, 2)
	testing.expect_value(t, s.bytes, 200)
	testing.expect_value(t, s.evictions, 1)
	_, hit = get(&c, 2)
	testing.expect(t, !hit)
	testing.expect(t, !os.exists(b), "the evicted file is gone")
	testing.expect(t, os.exists(a) && os.exists(d))
	testing.expect_value(t, stats(&c).misses, 1)
	testing.expect_value(t, stats(&c).hits, 1)
}

@(private = "file")
keep_odd :: proc(user: rawptr, key: Key) -> bool {
	return u64(key) % 2 == 1
}

@(private = "file")
Key :: type_of(Entry{}.key)

@(test)
kept_entries_survive_and_the_budget_bends :: proc(t: ^testing.T) {
	c: Cache
	init(&c, 150)
	defer destroy(&c)
	put(&c, 1, temp_file("cache-k1"), 100, keep_odd)
	put(&c, 3, temp_file("cache-k3"), 100, keep_odd) // over budget, both kept
	testing.expect_value(t, stats(&c).entries, 2)
	put(&c, 2, temp_file("cache-k2"), 100, keep_odd) // 2 is newest; the odd ones stay
	s := stats(&c)
	testing.expect_value(t, s.entries, 3)
	testing.expect_value(t, s.evictions, 0)
	put(&c, 4, temp_file("cache-k4"), 100, keep_odd) // 2 is the least recent even: it goes
	s = stats(&c)
	testing.expect_value(t, s.evictions, 1)
	_, hit := get(&c, 2)
	testing.expect(t, !hit)
	_, hit = get(&c, 1)
	testing.expect(t, hit)
}

@(test)
a_put_over_an_entry_replaces_it :: proc(t: ^testing.T) {
	c: Cache
	init(&c, 1000)
	defer destroy(&c)
	put(&c, 7, temp_file("cache-r"), 100)
	put(&c, 7, temp_file("cache-r"), 150)
	s := stats(&c)
	testing.expect_value(t, s.entries, 1)
	testing.expect_value(t, s.bytes, 150)
}
