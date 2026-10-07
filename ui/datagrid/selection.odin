package datagrid

import "core:mem"
import "core:strings"

// Row_Key names a row whatever its place: the order changes with a sort,
// a filter or a page arriving, and what is selected must not. It is the
// hash of the row's own key string (row_key), a table's or a page's.
Row_Key :: distinct u64

// Selection is the selected rows, by key. Explicit, keys are the rows
// selected. all selects every row that matches the filters and search of
// match (a hash of them; see match_hash), keys then being the rows taken
// back out of it: over a remote, "all matching" names rows that were
// never loaded. Each key keeps its row's key string, so the caller can
// act on rows that have scrolled out of a remote's cache.
//
// anchor is where a Shift range starts, and base the selection as it
// stood when the anchor was set, so a second Shift click replaces the
// range the first made rather than adding to it.
Selection :: struct {
	all:        bool,
	match:      u64,
	keys:       map[Row_Key]string,
	anchor:     Row_Key,
	has_anchor: bool,
	base:       map[Row_Key]string,
	base_all:   bool,
	allocator:  mem.Allocator,
}

selection_init :: proc(s: ^Selection, allocator := context.allocator) {
	s.allocator = allocator
	s.keys = make(map[Row_Key]string, allocator)
	s.base = make(map[Row_Key]string, allocator)
}

selection_destroy :: proc(s: ^Selection) {
	drop_keys(&s.keys, s.allocator)
	drop_keys(&s.base, s.allocator)
	delete(s.keys)
	delete(s.base)
	s^ = {}
}

@(private)
drop_keys :: proc(m: ^map[Row_Key]string, allocator: mem.Allocator) {
	for _, v in m {
		delete(v, allocator)
	}
	clear(m)
}

// selected reports whether the row keyed key is selected.
selected :: proc(s: ^Selection, key: Row_Key) -> bool {
	_, in_keys := s.keys[key]
	return in_keys != s.all
}

// selection_empty reports whether nothing is selected. A select-all with
// every row taken back out still counts as something: the grid cannot
// know the matching rows are all in keys.
selection_empty :: proc(s: ^Selection) -> bool {
	return !s.all && len(s.keys) == 0
}

// selection_count is how many rows are selected, out of matching rows
// that match: exact when explicit, and all-matching less what was taken
// out otherwise.
selection_count :: proc(s: ^Selection, matching: int) -> int {
	if s.all {
		return max(matching - len(s.keys), 0)
	}
	return len(s.keys)
}

// selection_clear selects nothing and forgets the anchor.
selection_clear :: proc(s: ^Selection) {
	drop_keys(&s.keys, s.allocator)
	drop_keys(&s.base, s.allocator)
	s.all, s.base_all, s.has_anchor = false, false, false
}

// mark puts key in m, keeping its string.
@(private)
mark :: proc(s: ^Selection, m: ^map[Row_Key]string, key: Row_Key, name: string) {
	if _, ok := m[key]; ok {
		return
	}
	m[key] = strings.clone(name, s.allocator) if name != "" else ""
}

@(private)
unmark :: proc(s: ^Selection, m: ^map[Row_Key]string, key: Row_Key) {
	if v, ok := m[key]; ok {
		delete(v, s.allocator)
		delete_key(m, key)
	}
}

// set_selected selects key (on) or deselects it, whichever mode s is in.
set_selected :: proc(s: ^Selection, key: Row_Key, name: string, on: bool) {
	if on != s.all {
		mark(s, &s.keys, key, name)
	} else {
		unmark(s, &s.keys, key)
	}
}

// selection_only selects key alone, a plain click, and anchors there.
selection_only :: proc(s: ^Selection, key: Row_Key, name: string) {
	selection_clear(s)
	mark(s, &s.keys, key, name)
	selection_anchor(s, key)
}

// selection_toggle flips key, a Cmd or Ctrl click or Space, and anchors
// there.
selection_toggle :: proc(s: ^Selection, key: Row_Key, name: string) {
	set_selected(s, key, name, !selected(s, key))
	selection_anchor(s, key)
}

// selection_anchor starts a range at key, remembering the selection as it
// stands as the base a range adds to.
selection_anchor :: proc(s: ^Selection, key: Row_Key) {
	s.anchor, s.has_anchor = key, true
	drop_keys(&s.base, s.allocator)
	for k, v in s.keys {
		mark(s, &s.base, k, v)
	}
	s.base_all = s.all
}

// selection_range makes the selection the base plus the rows of a Shift
// range: keys and names, the rows from the anchor to the row extended to,
// in order, each selected. Without an anchor the first key is the anchor.
selection_range :: proc(s: ^Selection, keys: []Row_Key, names: []string) {
	if !s.has_anchor && len(keys) > 0 {
		selection_anchor(s, keys[0])
	}
	drop_keys(&s.keys, s.allocator)
	for k, v in s.base {
		mark(s, &s.keys, k, v)
	}
	s.all = s.base_all
	for k, i in keys {
		set_selected(s, k, names[i] if i < len(names) else "", true)
	}
}

// selection_all selects every row matching match, taking none out.
selection_all :: proc(s: ^Selection, match: u64) {
	selection_clear(s)
	s.all, s.match = true, match
}

// selection_settle keeps s meaning what it did once the filters or the
// search change to match: explicit keys stay, and a select-all taken
// under another match becomes the loaded rows it covered, keys and names,
// since the rows it named are no longer the rows that match. A sort,
// which changes no match, changes nothing.
selection_settle :: proc(s: ^Selection, match: u64, loaded: []Row_Key, names: []string) {
	if !s.all || s.match == match {
		return
	}
	out := make(map[Row_Key]string, s.allocator)
	for k, i in loaded {
		if _, gone := s.keys[k]; !gone {
			out[k] =
				strings.clone(names[i], s.allocator) if i < len(names) && names[i] != "" else ""
		}
	}
	drop_keys(&s.keys, s.allocator)
	delete(s.keys)
	s.keys = out
	s.all = false
	drop_keys(&s.base, s.allocator)
	s.has_anchor = false
}
