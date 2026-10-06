package datagrid

// Heights is where each row of the current order starts, for a jump or a
// scroll bar to land exactly. With one height for every row (uniform) it
// is arithmetic and holds nothing; with a height per row it is a Fenwick
// tree of them, so the top of row i and the row at a y are each
// O(log n), and one row changing height is O(log n) too. Sums are f64:
// a hundred thousand rows of 33px come to 3.3 million pixels, where an
// f32 resolves only quarter pixels.
Heights :: struct {
	uniform: f64, // > 0: every row is this tall, and tree is unused
	n:       int,
	tree:    [dynamic]f64, // 1-based Fenwick tree over the rows' heights
	each:    [dynamic]f64, // each row's own height, for heights_of
	top_bit: int, // the highest power of two not above n, for the descent
}

heights_destroy :: proc(h: ^Heights) {
	delete(h.tree)
	delete(h.each)
	h^ = {}
}

// heights_set_uniform makes h n rows each height tall.
heights_set_uniform :: proc(h: ^Heights, n: int, height: f64) {
	h.uniform = max(height, 1)
	h.n = max(n, 0)
	clear(&h.tree)
	clear(&h.each)
}

// heights_build makes h n rows, row i height_of(user, i) tall (at least
// 1), in O(n).
heights_build :: proc(
	h: ^Heights,
	n: int,
	height_of: proc(user: rawptr, i: int) -> f64,
	user: rawptr,
) {
	h.uniform = 0
	h.n = max(n, 0)
	resize(&h.tree, h.n + 1)
	resize(&h.each, h.n)
	h.tree[0] = 0
	for i in 0 ..< h.n {
		v := max(height_of(user, i), 1)
		h.each[i] = v
		h.tree[i + 1] = v
	}
	for i in 1 ..= h.n {
		parent := i + (i & -i)
		if parent <= h.n {
			h.tree[parent] += h.tree[i]
		}
	}
	h.top_bit = 1
	for h.top_bit * 2 <= h.n {
		h.top_bit *= 2
	}
}

// heights_set changes row i's height to v.
heights_set :: proc(h: ^Heights, i: int, v: f64) {
	if h.uniform > 0 || i < 0 || i >= h.n {
		return
	}
	tall := max(v, 1)
	d := tall - h.each[i]
	h.each[i] = tall
	for j := i + 1; j <= h.n; j += j & -j {
		h.tree[j] += d
	}
}

// heights_top is where row i starts: the sum of the rows before it.
// i may be n, the bottom of the last row.
heights_top :: proc(h: ^Heights, i: int) -> f64 {
	n := clamp(i, 0, h.n)
	if h.uniform > 0 {
		return f64(n) * h.uniform
	}
	s: f64
	for j := n; j > 0; j -= j & -j {
		s += h.tree[j]
	}
	return s
}

// heights_of is row i's height.
heights_of :: proc(h: ^Heights, i: int) -> f64 {
	if h.uniform > 0 {
		return h.uniform
	}
	if i < 0 || i >= h.n {
		return 0
	}
	return h.each[i]
}

// heights_total is the height of every row.
heights_total :: proc(h: ^Heights) -> f64 {
	return heights_top(h, h.n)
}

// heights_at is the row y lies in: the last row starting at or above y,
// clamped to the rows there are (0 when there are none).
heights_at :: proc(h: ^Heights, y: f64) -> int {
	if h.n == 0 || y <= 0 {
		return 0
	}
	if h.uniform > 0 {
		return min(int(y / h.uniform), h.n - 1)
	}
	// Descend the tree: the largest i whose prefix sum is at most y.
	pos := 0
	rest := y
	for step := h.top_bit; step > 0; step >>= 1 {
		next := pos + step
		if next <= h.n && h.tree[next] <= rest {
			pos = next
			rest -= h.tree[next]
		}
	}
	return min(pos, h.n - 1)
}
