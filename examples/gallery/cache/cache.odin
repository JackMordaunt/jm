/*
Package cache is the gallery's picture cache: the files the generator
wrote, least recently used first out, within a byte budget. A stream
asks it before making a picture and tells it after, so a tile scrolled
back to within the budget costs nothing and one beyond it is made again.
Evicting deletes the file. An entry the caller says to keep, one a frame
still shows, is passed over, so the budget is a target the live set may
exceed rather than a cliff a picture on screen can fall off.

Any thread may call it; the counts are for the header.
*/
package gallery_cache

import "core:mem"
import "core:os"
import "core:sync"

import "jm:ui"

Entry :: struct {
	key:        ui.Need_Key,
	path:       string,
	size:       int,
	prev, next: ^Entry, // most recent at head
}

Stats :: struct {
	entries:   int,
	bytes:     int,
	hits:      int,
	misses:    int,
	evictions: int,
}

Cache :: struct {
	mutex:     sync.Mutex,
	allocator: mem.Allocator,
	budget:    int,
	entries:   map[ui.Need_Key]^Entry,
	head:      ^Entry,
	tail:      ^Entry,
	stats:     Stats,
}

// Keep says whether an entry must survive an eviction pass.
Keep :: proc(user: rawptr, key: ui.Need_Key) -> bool

init :: proc(c: ^Cache, budget: int, allocator := context.allocator) {
	c.allocator = allocator
	c.budget = budget
	c.entries = make(map[ui.Need_Key]^Entry, allocator)
}

// destroy forgets every entry, walking the list from head, and leaves
// the files.
destroy :: proc(c: ^Cache) {
	for e := c.head; e != nil; {
		next := e.next
		delete(e.path, c.allocator)
		free(e, c.allocator)
		e = next
	}
	c.head, c.tail = nil, nil
	delete(c.entries)
	c^ = {}
}

// get is the path cached for key, made the most recent; a miss counts.
get :: proc(c: ^Cache, key: ui.Need_Key) -> (path: string, ok: bool) {
	sync.mutex_guard(&c.mutex)
	e, found := c.entries[key]
	if !found {
		c.stats.misses += 1
		return "", false
	}
	c.stats.hits += 1
	unlink(c, e)
	push(c, e)
	return e.path, true
}

// put records that path, size bytes, now holds the picture for key, as
// the most recent entry, and evicts the least recent until the budget
// holds, deleting their files. Entries keep says to keep are skipped.
put :: proc(c: ^Cache, key: ui.Need_Key, path: string, size: int, keep: Keep = nil, user: rawptr = nil) {
	sync.mutex_guard(&c.mutex)
	if e, found := c.entries[key]; found {
		c.stats.bytes -= e.size
		unlink(c, e)
		delete(e.path, c.allocator)
		free(e, c.allocator)
		delete_key(&c.entries, key)
		c.stats.entries -= 1
	}
	e := new(Entry, c.allocator)
	e.key = key
	e.path = make_path(path, c.allocator)
	e.size = size
	c.entries[key] = e
	c.stats.entries += 1
	c.stats.bytes += size
	push(c, e)
	// Walk from the least recent, skipping what must stay.
	victim := c.tail
	for c.stats.bytes > c.budget && victim != nil {
		older := victim.prev
		if victim != e && (keep == nil || !keep(user, victim.key)) {
			evict(c, victim)
		}
		victim = older
	}
}

// stats is a copy of the counts now.
stats :: proc(c: ^Cache) -> Stats {
	sync.mutex_guard(&c.mutex)
	return c.stats
}

@(private)
evict :: proc(c: ^Cache, e: ^Entry) {
	unlink(c, e)
	delete_key(&c.entries, e.key)
	c.stats.entries -= 1
	c.stats.bytes -= e.size
	c.stats.evictions += 1
	os.remove(e.path)
	delete(e.path, c.allocator)
	free(e, c.allocator)
}

@(private)
push :: proc(c: ^Cache, e: ^Entry) {
	e.prev = nil
	e.next = c.head
	if c.head != nil {
		c.head.prev = e
	}
	c.head = e
	if c.tail == nil {
		c.tail = e
	}
}

@(private)
unlink :: proc(c: ^Cache, e: ^Entry) {
	if e.prev != nil {
		e.prev.next = e.next
	} else if c.head == e {
		c.head = e.next
	}
	if e.next != nil {
		e.next.prev = e.prev
	} else if c.tail == e {
		c.tail = e.prev
	}
	e.prev, e.next = nil, nil
}

@(private)
make_path :: proc(s: string, allocator: mem.Allocator) -> string {
	out := make([]byte, len(s), allocator)
	copy(out, s)
	return string(out)
}
