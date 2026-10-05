/*
todo is TodoMVC as a jm application: the ui is a frame of plain data, the
decisions are pure, SQLite is the data engine, and a stream pipeline joins
them across three threads. The pieces are examples/todo's packages:

	todo        the commands the ui may send             (leaf)
	query       the reads the ui may need, and results   (leaf)
	title       domain: what makes a title one we keep   (pure)
	completion  domain: whether todos are done           (pure)
	logic       a command and its facts to one effect    (pure)
	store       the SQLite client: reads, writes         (io)
	app         the host: enriches, executes, wires      (io)
	view        the ui: input to commands                (ui)

This is the window around app.

	todo                open todo.db in the working directory
	todo path.db        another database
	todo -memory        a database that is gone when the window closes
*/
package main

import "core:os"

import "jm:sqlite3"
import "jm:ui/sdl"

import "../common"
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
	sdl.run({title = "todos", width = WIDTH, height = HEIGHT, ui = view.view, user = &m, fonts = common.fonts(), data = app.data_host(h)})
	app.stop(h)
}

