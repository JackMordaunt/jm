package main

import "core:fmt"
import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// Toast_Demo is the toast page's demo state: the queue, where it stacks,
// the long job a loading toast stands for, and what the toaster last
// reported.
Toast_Demo :: struct {
	queue:    primer.Toasts,
	position: int,
	job:      int, // the loading toast's id while the job runs
	started:  f64,
	last:     string,
}

// TOAST_JOB is how long the demo's job runs, in seconds, before its
// loading toast turns to success.
TOAST_JOB :: 3

TOAST_POSITIONS := [?]primer.Segment {
	{label = "Bottom end"},
	{label = "Bottom start"},
	{label = "Bottom"},
	{label = "Top end"},
	{label = "Top start"},
	{label = "Top"},
}

TOAST_WARNING :: primer.Toast_Options {
	action = "Review",
}
TOAST_SYNC_ERROR :: primer.Toast_Options {
	detail = "The service returned 503.",
	action = "Retry",
}
TOAST_JOB_ERROR :: primer.Toast_Options {
	detail = "Foreman timed out after 30s.",
	action = "Retry",
}

// page_toast is the toast page, on Primer CSS's Toast: the toasts stack
// in a corner of the window, not in the page, so the page is buttons
// that push them.
page_toast :: proc(gtx: ^ui.Ctx, m: ^Model) {
	d := &m.toast
	ui.column(gtx, gap = 10)
	kitchen.section(
		gtx,
		"Variants",
		"the icon band takes the variant's emphasis fill; error and loading stay until dismissed",
	)
	if ui.wrap(gtx, gap = 8) {
		if primer.button(gtx, "Default") {
			primer.toast_push(&d.queue, "Rig 12 was moved to Norway.")
		}
		if primer.button(gtx, "Success") {
			primer.toast_push(&d.queue, "Invoice sent.", .Success)
		}
		if primer.button(gtx, "Warning") {
			primer.toast_push(&d.queue, "3 rigs have no pool account.", .Warning, TOAST_WARNING)
		}
		if primer.button(gtx, "Error") {
			primer.toast_push(&d.queue, "Could not sync with QuickBooks.", .Error, TOAST_SYNC_ERROR)
		}
		if primer.button(gtx, "Show every variant") {
			push_every_toast(d)
		}
	}
	kitchen.section(gtx, "A long job", "a loading toast updated in place when the job ends")
	run_toast_job(gtx, d)
	kitchen.section(gtx, "Position", "newest nearest the edge; 16px from it, 8px under 544px")
	primer.segmented_control(gtx, TOAST_POSITIONS[:], &d.position, "Position")
	last := d.last if d.last != "" else "nothing yet"
	primer.text(gtx, fmt.tprintf("Last: %s", last), .Small, color = primer.color(.Fg_Color_Muted))
	ev := primer.toaster(gtx, &d.queue, primer.Toast_Position(d.position))
	if ev.action != 0 {
		d.last = "action"
	} else if ev.dismissed != 0 {
		d.last = "dismissed"
	}
}

push_every_toast :: proc(d: ^Toast_Demo) {
	primer.toast_push(&d.queue, "Rig 12 was moved to Norway.")
	primer.toast_push(&d.queue, "Invoice sent.", .Success)
	primer.toast_push(&d.queue, "3 rigs have no pool account.", .Warning, TOAST_WARNING)
	primer.toast_push(&d.queue, "Could not sync with QuickBooks.", .Error, TOAST_SYNC_ERROR)
	primer.toast_push(&d.queue, "Syncing 40 rigs…", .Loading)
}

// run_toast_job starts a job shown by a loading toast, and turns the toast
// to success TOAST_JOB seconds later, or to an error when failed.
run_toast_job :: proc(gtx: ^ui.Ctx, d: ^Toast_Demo) {
	ui.wrap(gtx, gap = 8)
	if d.job == 0 {
		if primer.button(gtx, "Start a job") {
			d.job = primer.toast_push(&d.queue, "Syncing 40 rigs…", .Loading)
			d.started = gtx.time
		}
		return
	}
	if primer.button(gtx, "Fail the job") {
		primer.toast_update(&d.queue, d.job, "Sync failed.", .Error, TOAST_JOB_ERROR)
		d.job = 0
		return
	}
	if gtx.time - d.started >= TOAST_JOB {
		primer.toast_update(&d.queue, d.job, "Synced 40 rigs.", .Success)
		d.job = 0
		return
	}
	ui.request_frame(gtx, f32(TOAST_JOB - (gtx.time - d.started)))
}
