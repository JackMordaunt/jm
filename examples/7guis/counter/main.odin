/*
counter is 7GUIs task 1: a read-only count and a button that adds one to
it (https://eugenkiss.github.io/7guis/tasks#counter). The frame reads the
model and the click writes it; there is nothing to keep in sync.
*/
package main

import "core:fmt"

import "jm:ui"
import "jm:ui/fluent"

import "../shell"

Model :: struct {
	count: int,
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	ui.row(gtx, gap = 8, align = .Center)

	fluent.text(gtx, fmt.tprint(m.count), fluent.color(.Neutral_Foreground1), .S400, width = 80)
	if fluent.button(gtx, "Count") {
		m.count += 1
	}
}

main :: proc() {
	m: Model
	shell.run("Counter", 260, 70, view, &m)
}
