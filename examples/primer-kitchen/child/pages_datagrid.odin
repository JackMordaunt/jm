package main

import "core:encoding/cbor"
import "core:fmt"
import "core:strconv"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/primer"

import "../../kitchen"

// The Data table page, on the primer-kit's components/data-table.json:
// Primer's DataTable as jm:ui/datagrid draws it. A hundred thousand rigs
// in memory, the admin dashboard's biggest table; fifty thousand more
// paged from a simulated server that answers late, out of order and now
// and then not at all; a grouped table and an empty one; and the
// pagination bar Table.Pagination is on its own.

Data_Grids :: struct {
	ready:  bool,
	rigs:   primer.Data_Grid,
	cells:  [][RIG_COLUMN_COUNT]string,
	remote: primer.Data_Grid,
	paging: datagrid.Paging,
	server: Sim_Server,
	repos:  primer.Data_Grid,
	empty:  primer.Data_Grid,
	page:   int,
}

RIG_ROWS         :: 100_000
REMOTE_ROWS      :: 50_000
RIG_COLUMN_COUNT :: 12

RIG_COLUMNS := [RIG_COLUMN_COUNT]datagrid.Column {
	{id = "serial", title = "Serial", row_header = true, pin = .Left},
	{id = "model", title = "Model", filter = .Set},
	{id = "owner", title = "Owner", filter = .Set},
	{id = "facility", title = "Facility", filter = .Set},
	{id = "status", title = "Status", filter = .Set},
	{id = "payout", title = "Payout", filter = .Set},
	{id = "hashrate", title = "Hashrate", kind = .Number, align = .End},
	{id = "standing", title = "Standing", filter = .Set},
	{id = "created", title = "Created", kind = .Date},
	{id = "expected", title = "Expected worker", sizing = .Grow},
	{id = "worker", title = "F. Worker"},
	{id = "tags", title = "Tags", hidden = true},
}

@(rodata)
RIG_SITES := [5]string{"Norway", "Paraguay", "Wisconsin", "Ethiopia", "South Dakota"}
@(rodata)
RIG_MODELS := [4]string {
	"Bitmain S21 XP 270TH",
	"Bitmain S19j Pro 104TH",
	"Whatsminer M60S",
	"Avalon A1466",
}
@(rodata)
RIG_STATUSES := [4]string{"Deployed", "Pre-deployment", "Maintenance", "Unassigned"}

// rig_cells is rig i's cells, the same every time it is asked.
rig_cells :: proc(i: int) -> (c: [RIG_COLUMN_COUNT]string) {
	owner := (i * 7919) % 4000
	c[0] = fmt.aprintf("SN-%07d", i)
	c[1] = RIG_MODELS[i % len(RIG_MODELS)]
	c[2] = fmt.aprintf("Customer %d", owner)
	c[3] = RIG_SITES[(i * 7) % len(RIG_SITES)]
	c[4] = RIG_STATUSES[(i * 3) % len(RIG_STATUSES)]
	c[5] = "Client" if i % 5 != 0 else "Saz"
	c[6] = fmt.aprintf("%.1f TH/s", f64((i * 37) % 3000) / 10)
	c[7] = "Paid up" if i % 9 != 0 else "Overdue"
	c[8] = fmt.aprintf("2026-%02d-%02d", 1 + i % 12, 1 + i % 28)
	c[9] = fmt.aprintf("cust%d.rig%d~happyNOsilver", owner, i)
	c[10] = fmt.aprintf("cust%d.rig%d", owner, i)
	c[11] = "" if i % 3 != 0 else "batch-7, retrofit"
	return
}

// grids_ready makes the page's rows and grids the first time it shows.
grids_ready :: proc(d: ^Data_Grids) {
	if d.ready {
		return
	}
	d.ready = true
	d.cells = make([][RIG_COLUMN_COUNT]string, RIG_ROWS)
	for &c, i in d.cells {
		c = rig_cells(i)
	}
	primer.data_grid_init(&d.rigs, RIG_COLUMNS[:])
	d.paging = {
		source     = "rigs",
		page_size  = 100,
		margin     = 2,
		capacity   = 24,
		keep_stale = true,
	}
	primer.data_grid_init(&d.remote, RIG_COLUMNS[:], &d.paging)
	primer.data_grid_init(&d.repos, REPO_COLUMNS[:])
	d.repos.grid.view.group = 1
	d.repos.grid.density = .Condensed
	primer.data_grid_init(&d.empty, REPO_COLUMNS[:])
	sim_ready(&d.server)
}

page_data_table :: proc(gtx: ^ui.Ctx, m: ^Model) {
	d := &m.grids
	grids_ready(d)
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(
		gtx,
		"100,000 rigs in memory",
		"sort by a header (Shift adds a key), filter from its button, drag an edge or the " +
		"header, Shift-click or Shift+arrows for a range, Cmd+C to copy; the Columns menu " +
		"exports, hides and pins",
	)
	{
		ui.sized(gtx, {min = {0, 560}, max = {ui.INF, 560}})
		primer.data_grid(gtx, &d.rigs, RIG_COLUMNS[:], rigs_source(d), "Rigs")
	}
	remote_section(gtx, d)
	kitchen.section(
		gtx,
		"Grouped and empty",
		"rows grouped by a column, a group shut by a click or Enter; a table with no rows says so",
	)
	{
		ui.sized(gtx, {min = {0, 300}, max = {ui.INF, 300}})
		primer.data_grid(
			gtx,
			&d.repos,
			REPO_COLUMNS[:],
			repos_source(),
			"Repositories",
			toolbar = false,
		)
	}
	{
		ui.sized(gtx, {min = {0, 140}, max = {ui.INF, 140}})
		primer.data_grid(gtx, &d.empty, REPO_COLUMNS[:], {}, "Empty", toolbar = false)
	}
	kitchen.section(
		gtx,
		"Table.Pagination",
		"a footer of pages, for a table that pages rather than scrolls",
	)
	{
		primer.data_table_heading(
			gtx,
			"Repositories",
			"Primer's public repositories",
			divider = true,
		)
		primer.button(gtx, "New repository", .Primary, size = .Small, key = 3)
	}
	primer.data_table_pagination(gtx, "Repository pages", &d.page, 200, 10)
}

// remote_section is the paged grid and the controls of its server.
remote_section :: proc(gtx: ^ui.Ctx, d: ^Data_Grids) {
	s := &d.server
	note := fmt.tprintf(
		"pages of 100 asked for as they scroll near, answered %dms late or more, %d%% failing",
		int(s.latency * 1000),
		s.fail,
	)
	kitchen.section(gtx, "50,000 rigs from a server", note)
	{
		ui.wrap(gtx, gap = 8, align = .Center)
		if primer.button(gtx, "Resume server" if s.paused else "Pause server", key = 1) {
			s.paused = !s.paused
		}
		if primer.button(gtx, fmt.tprintf("Failures: %d%%", s.fail), key = 2) {
			s.fail = (s.fail + 10) % 40
		}
	}
	{
		ui.sized(gtx, {min = {0, 420}, max = {ui.INF, 420}})
		primer.data_grid(gtx, &d.remote, RIG_COLUMNS[:], {paged = &d.paging}, "Remote rigs")
	}
	if sim_pump(s, gtx.time) {
		ui.request_frame(gtx, 0.05)
	}
}

rigs_source :: proc(d: ^Data_Grids) -> datagrid.Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Data_Grids)(user).cells[row][col]
	}
	return {user = d, rows = len(d.cells), text = text}
}

REPO_COLUMNS := [?]datagrid.Column {
	{id = "name", title = "Repository", row_header = true},
	{id = "language", title = "Language", filter = .Set},
	{id = "updated", title = "Updated", kind = .Date},
	{id = "stars", title = "Stars", kind = .Number, align = .End},
}

@(rodata)
REPO_ROWS := [?][4]string {
	{"primer/react", "TypeScript", "2026-10-01", "3200"},
	{"primer/css", "SCSS", "2026-09-12", "12800"},
	{"primer/octicons", "JavaScript", "2026-08-30", "8100"},
	{"primer/primitives", "TypeScript", "2026-09-28", "420"},
	{"primer/view_components", "Ruby", "2026-09-30", "900"},
	{"primer/behaviors", "TypeScript", "2026-07-02", "75"},
	{"primer/doctocat", "JavaScript", "2025-12-15", "40"},
	{"primer/figma", "Figma", "2026-05-20", "12"},
}

repos_source :: proc() -> datagrid.Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		return REPO_ROWS[row][col]
	}
	return {rows = len(REPO_ROWS), text = text}
}

// Sim_Server is the paged grid's server, simulated in process: the
// application side of the kitchen's Data_Host. Each page or value list
// the grid needs is answered from a Memory_Table once the frame clock
// passes its due time, its latency plus a jitter drawn from its key;
// that draw also fails some of them. A need that goes before it is
// answered is cancelled. Clocked by the frames it is pumped from, it
// answers the same way in a headless render as in a window.
Sim_Server :: struct {
	host:    ui.Data_Host,
	inbox:   ui.Inbox,
	cells:   [][RIG_COLUMN_COUNT]string,
	rows:    []datagrid.Page_Row,
	table:   datagrid.Memory_Table,
	queue:   [dynamic]Sim_Request,
	clock:   f64,
	paused:  bool,
	latency: f64, // seconds
	jitter:  f64, // seconds, at most
	fail:    int, // percent
}

Sim_Request :: struct {
	need: ui.Need, // its own copy
	due:  f64,
	fail: bool,
}

// sim_init readies s as the host's application, before any frame.
sim_init :: proc(s: ^Sim_Server) {
	s.latency, s.jitter, s.fail = 0.3, 0.4, 5
	ui.inbox_init(&s.inbox)
	s.queue = make([dynamic]Sim_Request)
	s.host = {
		user    = s,
		inbox   = &s.inbox,
		on_need = sim_on_need,
	}
}

// sim_ready makes the server's rows, the first time the page shows.
sim_ready :: proc(s: ^Sim_Server) {
	s.cells = make([][RIG_COLUMN_COUNT]string, REMOTE_ROWS)
	s.rows = make([]datagrid.Page_Row, REMOTE_ROWS)
	for &c, i in s.cells {
		c = rig_cells(RIG_ROWS + i)
		s.rows[i] = {
			key   = c[0],
			cells = c[:],
		}
	}
	datagrid.memory_table_init(&s.table, RIG_COLUMNS[:], s.rows)
}

sim_on_need :: proc(user: rawptr, n: ui.Need, added: bool) {
	s := (^Sim_Server)(user)
	if !added {
		for r, i in s.queue {
			if r.need.key == n.key {
				sim_free(r)
				unordered_remove(&s.queue, i)
				return
			}
		}
		return
	}
	if !ui.need_is(n, datagrid.Page_Query) && !ui.need_is(n, datagrid.Values_Query) {
		return
	}
	draw := u64(n.key) * 0x9E3779B97F4A7C15
	r := Sim_Request {
		need = {n.key, clone(n.kind), transmute([]u8)clone(string(n.query))},
		due  = s.clock + s.latency + s.jitter * f64(draw >> 40 & 0xffff) / 0xffff,
		fail = int(draw >> 20 & 0xff) % 100 < s.fail,
	}
	append(&s.queue, r)
}

@(private = "file")
clone :: proc(s: string) -> string {
	out := make([]u8, len(s))
	copy(out, s)
	return string(out)
}

sim_free :: proc(r: Sim_Request) {
	delete(r.need.kind)
	delete(r.need.query)
}

// sim_pump answers what is due by now, unless the server is paused, and
// reports whether anything waits still.
sim_pump :: proc(s: ^Sim_Server, now: f64) -> bool {
	s.clock = now
	if s.paused || s.rows == nil {
		return len(s.queue) > 0
	}
	for i := 0; i < len(s.queue); {
		r := s.queue[i]
		if r.due > now {
			i += 1
			continue
		}
		sim_answer(s, r)
		sim_free(r)
		unordered_remove(&s.queue, i)
	}
	return len(s.queue) > 0
}

// sim_answer puts r's answer in the inbox for the next frame.
sim_answer :: proc(s: ^Sim_Server, r: Sim_Request) {
	bytes: []u8
	if q, ok := ui.need_as(r.need, datagrid.Page_Query); ok {
		page := datagrid.Page {
			error = "the server timed out",
		}
		if !r.fail {
			page = datagrid.answer_page(&s.table, q, context.temp_allocator)
		}
		bytes, _ = cbor.marshal_into_bytes(
			page,
			allocator = context.temp_allocator,
			temp_allocator = context.temp_allocator,
		)
	} else if v, vok := ui.need_as(r.need, datagrid.Values_Query); vok {
		values := datagrid.answer_values(&s.table, v, context.temp_allocator)
		bytes, _ = cbor.marshal_into_bytes(
			values,
			allocator = context.temp_allocator,
			temp_allocator = context.temp_allocator,
		)
	}
	if bytes != nil {
		ui.inbox_put(&s.inbox, r.need.key, bytes)
	}
}

// grid_flag is the kitchen's own flags for a headless session of this
// page: -grid-pause holds the server's answers and -grid-resume lets them
// go (-advance N, a step, runs the frame clock they come due by);
// -remote-scroll Y scrolls the paged grid's rows to Y.
grid_flag :: proc(user: rawptr, args: []string, i: ^int) -> bool {
	m := (^Model)(user)
	switch args[i^] {
	case "-grid-pause":
		m.grids.server.paused = true
	case "-grid-resume":
		m.grids.server.paused = false
	case "-remote-scroll":
		if i^ + 1 >= len(args) {
			return false
		}
		i^ += 1
		y, _ := strconv.parse_f32(args[i^])
		m.grids.remote.grid.scroll.y = y
	case:
		return false
	}
	return true
}
