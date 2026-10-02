package ui

import "core:testing"
import "jm:ui/ops"

// A contract as an application would declare it: queries the ui needs,
// their shapes, and the commands it emits. The ui proc below depends on
// these and on nothing of the application.

@(private = "file")
Users_Page :: struct {
	page, size: int,
}

@(private = "file")
User_Row :: struct {
	id:   int,
	name: string,
}

@(private = "file")
Users_Page_Result :: struct {
	rows:  []User_Row,
	total: int,
}

@(private = "file")
Avatar :: struct {
	user, px: int,
}

@(private = "file")
Avatar_Result :: struct {
	image: u32,
}

@(private = "file")
Delete_User :: struct {
	id: int,
}

@(private = "file")
Table_Model :: struct {
	page:     int,
	px:       int,
	skeleton: int, // rows drawn as placeholders in the last frame
	drawn:    [dynamic]string, // names drawn in the last frame
	images:   [dynamic]u32, // avatar images drawn in the last frame
	stale:    bool, // the page was Stale in the last frame
}

// A user table: it needs its page, draws a skeleton until it comes, needs
// an avatar for each row at the size layout picked, and emits a delete for
// the row clicked. Each row's area is tagged with its name.
@(private = "file")
table_ui :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Table_Model)(user)
	m.skeleton = 0
	m.stale = false
	clear(&m.drawn)
	clear(&m.images)
	page, status := need(gtx, Users_Page{page = m.page, size = 2}, Users_Page_Result)
	if status == .Missing || status == .Loading {
		m.skeleton = 2
		return
	}
	m.stale = status == .Stale
	for row, ii in page.rows {
		s := scope_open(gtx, row.id)
		defer scope_close(&s)
		append(&m.drawn, row.name)
		avatar, av := need(gtx, Avatar{user = row.id, px = m.px}, Avatar_Result)
		if av == .Ready {
			append(&m.images, avatar.image)
		}
		area := ops.Area_Id(100 + row.id)
		ops.input_area(gtx.scene, area, ops.Rect{0, f32(ii) * 20, 200, 20}, {.Press, .Release})
		ops.tag(gtx.scene, area, row.name)
		for e in events(gtx, area) {
			if e.kind == .Release {
				command(gtx, Delete_User{id = row.id})
			}
		}
	}
}

@(private = "file")
table_probe :: proc(m: ^Table_Model) -> Probe {
	p: Probe
	m.px = 48
	probe_init(&p, table_ui, m, {400, 300})
	return p
}

@(test)
need_asks_then_renders_what_is_delivered :: proc(t: ^testing.T) {
	m: Table_Model
	defer delete(m.drawn)
	defer delete(m.images)
	p := table_probe(&m)
	defer probe_destroy(&p)

	// The first frame asks for its page and draws a skeleton.
	testing.expect_value(t, m.skeleton, 2)
	needs := probe_needs(&p)
	testing.expect_value(t, len(needs), 1)
	q, ok := need_as(needs[0], Users_Page)
	testing.expect(t, ok)
	testing.expect_value(t, q, Users_Page{page = 0, size = 2})
	testing.expect_value(t, len(probe_added(&p)), 1)

	// The page arrives: rows draw, and each asks for its avatar at 48px.
	rows := []User_Row{{1, "Ann"}, {2, "Bo"}}
	probe_deliver(&p, Users_Page{page = 0, size = 2}, Users_Page_Result{rows = rows, total = 2})
	probe_frame(&p)
	testing.expect_value(t, m.skeleton, 0)
	testing.expect_value(t, len(m.drawn), 2)
	testing.expect_value(t, m.drawn[0], "Ann")
	testing.expect_value(t, len(probe_needs(&p)), 3)
	testing.expect(t, probe_needs_q(&p, Avatar{user = 1, px = 48}))
	testing.expect(t, probe_needs_q(&p, Avatar{user = 2, px = 48}))
	testing.expect_value(t, len(probe_added(&p)), 2)
	testing.expect_value(t, len(probe_dropped(&p)), 0)

	// One avatar lands; only that row draws an image.
	probe_deliver(&p, Avatar{user = 2, px = 48}, Avatar_Result{image = 7})
	probe_frame(&p)
	testing.expect_value(t, len(m.images), 1)
	testing.expect_value(t, m.images[0], u32(7))

	// A click on a row is a command for the application, typed.
	testing.expect(t, probe_click(&p, "Bo"))
	cmds := probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	c, cok := command_as(cmds[0], Delete_User)
	testing.expect(t, cok)
	testing.expect_value(t, c.id, 2)
	testing.expect(t, !command_is(cmds[0], Users_Page))
}

@(test)
need_releases_what_a_frame_stops_asking :: proc(t: ^testing.T) {
	m: Table_Model
	defer delete(m.drawn)
	defer delete(m.images)
	p := table_probe(&m)
	defer probe_destroy(&p)
	rows := []User_Row{{1, "Ann"}, {2, "Bo"}}
	probe_deliver(&p, Users_Page{page = 0, size = 2}, Users_Page_Result{rows = rows, total = 2})
	probe_frame(&p)
	testing.expect_value(t, len(probe_added(&p)), 2)

	// Turning the page drops the old page's need and its rows' avatars, and
	// asks for the new page: three dropped, one added.
	m.page = 1
	probe_frame(&p)
	testing.expect_value(t, len(probe_dropped(&p)), 3)
	testing.expect_value(t, len(probe_added(&p)), 1)
	testing.expect(t, probe_needs_q(&p, Users_Page{page = 1, size = 2}))
	testing.expect(t, !probe_needs_q(&p, Users_Page{page = 0, size = 2}))
	testing.expect_value(t, m.skeleton, 2)

	// A delivery for the dropped need is a shape nobody asks for: the
	// layout keeps it through the frame after, then drops it. Nothing
	// draws from it.
	probe_deliver(&p, Avatar{user = 1, px = 48}, Avatar_Result{image = 3})
	probe_frame(&p)
	probe_frame(&p)
	testing.expect_value(t, len(p.layout.shapes), 1)
	probe_frame(&p)
	testing.expect_value(t, len(m.images), 0)
	testing.expect_value(t, len(p.layout.shapes), 0)
}

@(test)
need_stale_keeps_the_shape :: proc(t: ^testing.T) {
	m: Table_Model
	defer delete(m.drawn)
	defer delete(m.images)
	p := table_probe(&m)
	defer probe_destroy(&p)
	rows := []User_Row{{1, "Ann"}, {2, "Bo"}}
	probe_deliver(&p, Users_Page{page = 0, size = 2}, Users_Page_Result{rows = rows, total = 2})
	probe_frame(&p)
	testing.expect_value(t, len(m.drawn), 2)

	// The host says the page is being refreshed: the rows stay up, marked.
	probe_deliver_raw(&p, key_of(Users_Page{page = 0, size = 2}), nil, .Stale)
	probe_frame(&p)
	testing.expect(t, m.stale)
	testing.expect_value(t, len(m.drawn), 2)
	testing.expect_value(t, m.drawn[1], "Bo")

	// The refresh lands with one row fewer; the old decode is replaced.
	probe_deliver(&p, Users_Page{page = 0, size = 2}, Users_Page_Result{rows = rows[:1], total = 1})
	probe_frame(&p)
	testing.expect(t, !m.stale)
	testing.expect_value(t, len(m.drawn), 1)
}

@(test)
need_same_query_twice_is_one_need :: proc(t: ^testing.T) {
	twice :: proc(gtx: ^Ctx, user: rawptr) {
		need(gtx, Users_Page{page = 0, size = 2}, Users_Page_Result)
		need(gtx, Users_Page{page = 0, size = 2}, Users_Page_Result)
		need(gtx, Users_Page{page = 1, size = 2}, Users_Page_Result)
	}
	p: Probe
	probe_init(&p, twice, nil, {100, 100})
	defer probe_destroy(&p)
	testing.expect_value(t, len(probe_needs(&p)), 2)
	testing.expect_value(t, probe_needs(&p)[0].kind, "ui.Users_Page")
	testing.expect_value(t, probe_needs(&p)[0].key, key_of(Users_Page{page = 0, size = 2}))
}

@(test)
inbox_last_put_wins_and_drains_once :: proc(t: ^testing.T) {
	ib: Inbox
	inbox_init(&ib)
	defer inbox_destroy(&ib)
	l: Layout
	layout_init(&l)
	defer layout_destroy(&l)
	key := key_of(Users_Page{page = 0, size = 2})
	inbox_put(&ib, key, {1}, .Ready)
	inbox_put(&ib, key, {2}, .Ready)
	inbox_put(&ib, key, nil, .Stale)
	testing.expect(t, inbox_pending(&ib))
	testing.expect(t, inbox_drain(&ib, &l))
	testing.expect(t, !inbox_drain(&ib, &l))
	e, ok := l.shapes[key]
	testing.expect(t, ok)
	testing.expect_value(t, e.status, Status.Stale)
	testing.expect_value(t, len(e.data), 1)
	testing.expect_value(t, e.data[0], u8(2))
}

@(test)
subscriptions_diff_frame_to_frame :: proc(t: ^testing.T) {
	s: Subscriptions
	subscriptions_init(&s)
	defer subscriptions_destroy(&s)
	a := Need{1, "a", {1}}
	b := Need{2, "b", {2}}
	added, dropped := subscriptions_update(&s, {a, b})
	testing.expect_value(t, len(added), 2)
	testing.expect_value(t, len(dropped), 0)
	added, dropped = subscriptions_update(&s, {b})
	testing.expect_value(t, len(added), 0)
	testing.expect_value(t, len(dropped), 1)
	testing.expect_value(t, dropped[0].key, Need_Key(1))
	testing.expect_value(t, dropped[0].kind, "a")
	testing.expect(t, subscriptions_live(&s, 2))
	testing.expect(t, !subscriptions_live(&s, 1))
	added, dropped = subscriptions_update(&s, {})
	testing.expect_value(t, len(dropped), 1)
}
