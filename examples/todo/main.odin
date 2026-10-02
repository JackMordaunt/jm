/*
todo is TodoMVC as a jm application: the ui is a frame of plain data, the
rules are pure, SQLite is the data engine, and a stream pipeline joins them
across four threads. The pieces are examples/todo's packages: shapes is
the contract, view the ui, logic the rules, store the data engine, and app
the host that wires them; this is the window around app.

	todo                open todo.db in the working directory
	todo path.db        another database
	todo -memory        a database that is gone when the window closes
*/
package main

import "core:os"
import "core:strings"

import "jm:sqlite3"
import "jm:ui"
import "jm:ui/ops"
import "jm:ui/sdl"

import "app"
import "view"

WIDTH :: 720
HEIGHT :: 760

main :: proc() {
	path := "todo.db"
	if len(os.args) > 1 {
		path = os.args[1]
		if path == "-memory" {
			path = sqlite3.MEMORY
		}
	}
	h := new(app.Host)
	defer free(h)
	if !app.init(h, path, sdl.wake) {
		os.exit(1)
	}
	m: view.Model
	defer view.model_destroy(&m)
	sdl.run({title = "todos", width = WIDTH, height = HEIGHT, ui = view.view, user = &m, fonts = app_fonts(), data = app.data_host(h)})
	app.stop(h)
}

// app_fonts is Selawik at regular, semibold and bold, the Fluent kit's
// open stand-in for Segoe UI, from the user's font directory (just
// fluent-fonts fetches it), or jm:ui's default font for all three.
app_fonts :: proc() -> []ops.Font_Ref {
	dir := strings.concatenate({os.get_env("HOME", context.allocator), "/.local/share/fonts/selawik/"})
	names := [3]string{"selawk.ttf", "selawksb.ttf", "selawkb.ttf"}
	fonts := make([]ops.Font_Ref, 3)
	for n, ii in names {
		p := strings.concatenate({dir, n})
		fonts[ii] = {ops.Font_Id(ii), os.exists(p) ? p : ui.default_font()}
	}
	return fonts
}
