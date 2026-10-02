package todo_app

import "core:testing"
import "core:time"

import "jm:sqlite3"
import "jm:ui"

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
	deadline := time.tick_now()._nsec + i64(3 * time.Second)
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
	// problem list, in memory, is delivered as a shape.
	testing.expect(t, ui.probe_click(&r.p, "New todo"))
	ui.probe_type(&r.p, "   ")
	ui.probe_key(&r.p, .Enter)
	hand_on(&r)
	testing.expect(t, settle(&r, "Dismiss"), "the problem bar appeared")
	rows, err := sqlite3.query(r.h.store.db, "SELECT COUNT(*) FROM todo", allocator = context.temp_allocator)
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
	for _ in 0 ..< 200 {
		if len(r.h.route.live) == 1 {
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect_value(t, len(r.h.route.live), 1)
	testing.expect(t, r.m.filter == .Active)
}
