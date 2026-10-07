package datagrid

import "jm:ui"
import "jm:ui/ops"

// Auto widths: a column sized Auto or Grow is as wide as its widest cell,
// sampled. A table's grid samples MEASURE_SAMPLE rows spread through
// all its rows when they change (not when they are sorted or filtered,
// which would make the columns jump as the user types a search); a
// remote's samples the rows it holds once its query's first page is in.

// MEASURE_SAMPLE is the most rows a measure reads.
MEASURE_SAMPLE :: 200

// measure sets every Auto and Grow column's measured width when what it
// was measured for has changed.
@(private)
measure :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Rows, skin: ^Skin) {
	key := measure_key(src)
	if key == 0 || key == g.measured {
		return
	}
	g.measured = key
	for c, i in cols {
		if c.sizing != .Fixed {
			g.view.cols[i].auto = fit_width(gtx, g, cols, src, skin, i)
		}
	}
}

// measure_key names what the widths would be measured for: a table's
// rows, a remote's query once a page of it is in; 0 when there is
// nothing to measure yet.
@(private)
measure_key :: proc(src: Rows) -> u64 {
	switch r in src {
	case ^Memory_Table:
		h := ui.fnv_u64(ui.fnv_u64(ui.FNV_OFFSET, u64(uintptr(r))), r.version)
		return ui.fnv_u64(h, u64(len(r.rows))) | 1
	case ^Remote_Rows:
		for e in r.pages.entries {
			if e.query == r.pages.query && e.state == .Ready {
				return r.pages.query | 1
			}
		}
	}
	return 0
}

// fit_width is column col's widest cell among the sampled rows, or its
// title with the header's controls if wider, padded.
fit_width :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Rows,
	skin: ^Skin,
	col: int,
) -> f32 {
	st := &skin.style
	font := st.font if st.font != 0 else gtx.font
	head := st.header_font if st.header_font != 0 else font
	size := st.text_size
	title := measure_text(
		gtx,
		head,
		st.header_size if st.header_size > 0 else size,
		cols[col].title,
	)
	w := title + st.header_extra
	if cols[col].row_number {
		w = max(w, measure_text(gtx, font, size, "0") * f32(digit_count(g.geo.items)))
	} else {
		switch r in src {
		case ^Memory_Table:
			w = max(w, sample_table(gtx, r.rows, font, size, col))
		case ^Remote_Rows:
			w = max(w, sample_pages(gtx, &r.pages, font, size, col))
		}
	}
	return w + 2 * st.pad + cols[col].extra
}

// digit_count is how many digits the row numbers up to n take.
@(private)
digit_count :: proc(n: int) -> int {
	digits := 1
	for k := max(n, 1); k >= 10; k /= 10 {
		digits += 1
	}
	return digits
}

// sample_table measures the first rows, which show first, and then rows
// spread through the rest by a golden-ratio stride, which no period in
// the data lines up with as a fixed stride can.
@(private)
sample_table :: proc(
	gtx: ^ui.Ctx,
	rows: []Page_Row,
	font: ops.Font_Id,
	size: f32,
	col: int,
) -> f32 {
	n := len(rows)
	w: f32
	head := min(n, MEASURE_SAMPLE / 4)
	for r in 0 ..< head {
		w = max(w, measure_text(gtx, font, size, row_text(rows, r, col)))
	}
	if n <= head {
		return w
	}
	at: u64
	for _ in head ..< min(n, MEASURE_SAMPLE) {
		at += 0x9E3779B97F4A7C15
		r := int((at >> 11) % u64(n))
		w = max(w, measure_text(gtx, font, size, row_text(rows, r, col)))
	}
	return w
}

@(private)
sample_pages :: proc(gtx: ^ui.Ctx, p: ^Pages, font: ops.Font_Id, size: f32, col: int) -> f32 {
	w: f32
	seen := 0
	for e in p.entries {
		if e.query != p.query || e.state != .Ready {
			continue
		}
		for r in e.rows {
			if col < len(r.cells) {
				w = max(w, measure_text(gtx, font, size, r.cells[col]))
			}
			seen += 1
			if seen >= MEASURE_SAMPLE {
				return w
			}
		}
	}
	return w
}

// measure_text is s's width, shaped into the frame: measuring reads many
// texts once, which the draw cache should not keep.
@(private)
measure_text :: proc(gtx: ^ui.Ctx, font: ops.Font_Id, size: f32, s: string) -> f32 {
	if s == "" {
		return 0
	}
	return ui.shape(gtx.shaper, font, size, s, gtx.allocator).advance
}
