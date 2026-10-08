package primer

import "core:testing"

import "jm:ui"

@(private = "file")
Undo_Model :: struct {
	name:      ui.Text_State,
	app_undos: int,
}

// undo_ui is a TextInput and an app's own undo shortcut beside it.
@(private = "file")
undo_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Undo_Model)(user)
	app := ui.claim_id(gtx, 90)
	ui.key_interest(gtx, app, .Z, {ui.SHORTCUT})
	for e in ui.events(gtx, app) {
		if e.kind == .Key {
			m.app_undos += 1
		}
	}
	text_input(gtx, &m.name, name = "Name", width = 300)
}

// A TextInput undoes its own typing first, and the app's undo hears the
// shortcut once the field has nothing left to undo.
@(test)
test_a_text_input_undoes_its_typing_before_the_app_does :: proc(t: ^testing.T) {
	m: Undo_Model
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, undo_ui, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Name"))
	ui.probe_type(&p, "Rig 7")
	ui.probe_key(&p, .Z, {ui.SHORTCUT})
	testing.expect_value(t, ui.text_string(&m.name), "")
	testing.expect_value(t, m.app_undos, 0)
	ui.probe_key(&p, .Z, {ui.SHORTCUT})
	testing.expect_value(t, m.app_undos, 1)
	ui.probe_key(&p, .Z, {ui.SHORTCUT, .Shift})
	testing.expect_value(t, ui.text_string(&m.name), "Rig 7")
}
