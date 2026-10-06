package todo_app

import "core:encoding/cbor"
import "core:testing"
import "core:time"

import "jm:sqlite3"
import "jm:ui"

import "../../common"
import "../query"
import "../store"
import "../todo"
import "../view"

// The whole application, less the window: the view runs in a probe, the
// probe's needs and commands go to the host as the frame loop would send
// them, and the host's answers are drained into the probe before the next
// frame. Everything between is the real pipeline on its real threads.

@(private = "file")
Rig :: struct {
	h:     Host,
	m:     view.Model,
	p:     ui.Probe,
	data:  ui.Data_Host,
	needs: ui.Subscriptions,
}

@(private = "file")
rig_open :: proc(r: ^Rig) -> bool {
	if !init(&r.h, sqlite3.MEMORY) {
		return false
	}
	r.data = data_host(&r.h)
	ui.subscriptions_init(&r.needs)
	ui.probe_init(&r.p, view.view, &r.m, {800, 600})
	return true
}

@(private = "file")
rig_close :: proc(r: ^Rig) {
	ui.probe_destroy(&r.p)
	ui.subscriptions_destroy(&r.needs)
	view.model_destroy(&r.m)
	stop(&r.h)
}

// hand_on does what the frame loop does after a frame: the need diff and
// the commands go to the host.
@(private = "file")
hand_on :: proc(r: ^Rig) {
	ui.data_after_frame(&r.data, &r.needs, &r.p.router)
}

// settle waits for the host to answer, drains the answers into the probe
// and runs a frame, until a frame finds the name present (or absent), or
// the deadline passes.
@(private = "file")
settle :: proc(r: ^Rig, name: string, present := true) -> bool {
	deadline := time.tick_now()._nsec + i64(30 * time.Second)
	for time.tick_now()._nsec < deadline {
		if ui.inbox_pending(&r.h.inbox) {
			ui.inbox_drain(&r.h.inbox, &r.p.layout)
			ui.probe_frame(&r.p)
			hand_on(r)
			if ui.probe_tagged(&r.p, name) == present {
				return true
			}
		}
		time.sleep(time.Millisecond)
	}
	return false
}

@(test)
a_todo_round_trips_through_the_rules_the_store_and_back :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	// The first frame needs the list; the host answers with an empty one.
	hand_on(&r)
	testing.expect(t, settle(&r, "0 items left"), "the empty list arrived")

	// Typing a todo and pressing Enter is an Add; the rules accept it,
	// the store commits it, the hook reports it, the query re-runs, and
	// the row lands in the frame.
	testing.expect(t, ui.probe_click(&r.p, "New todo"))
	ui.probe_type(&r.p, "  write the test ")
	ui.probe_key(&r.p, .Enter)
	hand_on(&r)
	testing.expect(t, settle(&r, "Delete write the test"), "the trimmed todo came back as a row")

	// A toggle flips it in the store; the Completed filter then shows it.
	testing.expect(t, ui.probe_click(&r.p, ""))
	hand_on(&r)
	testing.expect(t, settle(&r, "Clear completed"), "the footer saw a completed row")
	testing.expect(t, ui.probe_click(&r.p, "Completed"))
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, settle(&r, "Delete write the test"), "the completed page lists it")

	// Clearing completed deletes it; the page is empty again.
	testing.expect(t, ui.probe_click(&r.p, "Clear completed"))
	hand_on(&r)
	testing.expect(t, settle(&r, "Delete write the test", present = false), "the row is gone")
}

@(test)
a_refused_command_becomes_a_problem_that_dismisses :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r, "0 items left"))

	// A blank title never reaches the store: the rules refuse it and the
	// problem list, in memory, is delivered as a result.
	testing.expect(t, ui.probe_click(&r.p, "New todo"))
	ui.probe_type(&r.p, "   ")
	ui.probe_key(&r.p, .Enter)
	hand_on(&r)
	testing.expect(t, settle(&r, "Dismiss"), "the problem bar appeared")
	rows, err := sqlite3.query(r.h.stage.store.db, "SELECT COUNT(*) FROM todo", allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, sqlite3.next(&rows))
	testing.expect_value(t, sqlite3.integer(rows, 0), i64(0))
	sqlite3.finish(&rows)

	// Dismissing it is a command too, and the list comes back empty.
	testing.expect(t, ui.probe_click(&r.p, "Dismiss"))
	hand_on(&r)
	testing.expect(t, settle(&r, "Dismiss", present = false), "the problem is gone")
}

@(test)
dropping_a_need_stops_its_refreshes :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r, "0 items left"))
	testing.expect_value(t, len(r.h.route.live), 1)
	testing.expect(t, ui.probe_click(&r.p, "Active"))
	ui.probe_frame(&r.p)
	hand_on(&r)
	// The Active page lands, the frame after draws from it and drops the
	// All need; the route stage, on the pool, then forgets it.
	testing.expect(t, settle(&r, "0 items left"))
	ui.probe_frame(&r.p)
	hand_on(&r)
	// Live goes from All, through both, to Active alone: a count of one
	// holds before the Active need arrives too, so the filter is checked.
	only_active := false
	for start := time.tick_now(); !only_active && time.tick_since(start) < 30 * time.Second; {
		time.sleep(time.Millisecond)
		only_active = len(r.h.route.live) == 1
		for _, filter in r.h.route.live {
			only_active &&= filter == .Active
		}
	}
	testing.expect(t, only_active, "the All need was dropped and the Active need is live")
	testing.expect(t, r.m.filter == .Active)
}

@(test)
a_toggle_on_a_todo_gone_since_the_frame_is_a_problem :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r, "0 items left"))
	testing.expect(t, ui.probe_click(&r.p, "New todo"))
	ui.probe_type(&r.p, "brief")
	ui.probe_key(&r.p, .Enter)
	hand_on(&r)
	testing.expect(t, settle(&r, "Delete brief"))

	// The frame still draws the row after its delete has been sent, so a
	// toggle follows; the facts gathered for it say the row is gone.
	testing.expect(t, ui.probe_click(&r.p, "Delete brief"))
	hand_on(&r)
	testing.expect(t, ui.probe_click(&r.p, ""))
	hand_on(&r)
	testing.expect(t, settle(&r, "Dismiss"), "the toggle became a problem")
	testing.expect(t, settle(&r, "Delete brief", present = false), "the delete landed")
}

@(test)
a_problems_need_mounted_late_gets_the_current_list :: proc(t: ^testing.T) {
	// The db stage alone, on this thread: no pipeline is needed to ask it.
	s: Db_Stage
	s.allocator = context.allocator
	s.out = make([dynamic]common.Result)
	defer delete(s.out)
	testing.expect(t, store.open(&s.store, sqlite3.MEMORY, nil, nil))
	defer store.close(&s.store)

	problems_of :: proc(t: ^testing.T, s: ^Db_Stage, out: []common.Result) -> (res: query.Problems_Result) {
		testing.expect_value(t, len(out), 1)
		if len(out) == 1 {
			err := cbor.unmarshal_from_bytes(out[0].data, &res, allocator = context.temp_allocator)
			testing.expect(t, err == nil)
			delete(out[0].data, s.allocator)
		}
		return
	}

	// Before anything has gone wrong, the answer is an empty list, not none.
	none := problems_of(t, &s, db_apply(&s, Read{key = 5, q = query.Problems{}}))
	testing.expect_value(t, len(none.items), 0)

	// A refused Add reports the list as it changes...
	pushed := problems_of(t, &s, db_apply(&s, todo.Command(todo.Add{})))
	testing.expect_value(t, len(pushed.items), 1)

	// ...and a need that appears afterwards is answered with it, under its key.
	out := db_apply(&s, Read{key = 9, q = query.Problems{}})
	testing.expect(t, len(out) == 1 && out[0].key == 9)
	late := problems_of(t, &s, out)
	testing.expect_value(t, len(late.items), 1)
	testing.expect_value(t, late.items[0].message, "A todo needs a title.")
}
