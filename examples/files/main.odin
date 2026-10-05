/*
files is a file browser: a jm application on the model of examples/todo
and examples/gallery, over the real filesystem. A folder's listing and
each picture's thumbnail are needs the application answers on worker
threads; a double click on a folder goes into it, on a file opens it with
the system's application for it. It renames, makes folders, copies,
moves and moves to the Trash, asks when a paste would collide, and
undoes, through these packages:

	files       the commands the ui may send                (leaf)
	query       the reads the ui may need, and their results (leaf)
	naming      domain: what an entry may be called          (pure)
	placement   domain: how a paste reaches its folder       (pure)
	protection  domain: what must not be changed             (pure)
	logic       a command and its facts to a plan of effects (pure)
	fs, store   clients of the filesystem and of SQLite      (io)
	app         the host: enriches, executes, wires, watches (io)
	view        the ui: input to commands                    (ui)

	files               the home folder
	files path          another folder
*/
package main

import "core:os"

import "jm:ui/shell"

import "../common"
import "app"
import "view"

WIDTH :: 1100
HEIGHT :: 720

main :: proc() {
	path: string
	if len(os.args) > 1 {
		path = os.args[1]
	} else {
		home, err := os.user_home_dir(context.allocator)
		if err != nil {
			os.exit(1)
		}
		path = home
	}
	h := new(app.Host)
	defer free(h)
	if !app.init(h, shell.wake) {
		os.exit(1)
	}
	m: view.Model
	view.model_init(&m, path)
	defer view.model_destroy(&m)
	shell.run({title = "files", width = WIDTH, height = HEIGHT, min_width = view.MIN_WIDTH, min_height = view.MIN_HEIGHT, ui = view.view, user = &m, fonts = common.fonts(), data = app.data_host(h)})
	app.stop(h)
}

