/*
files is a file browser: a jm application on the model of examples/todo
and examples/gallery, over the real filesystem. A folder's listing and
each picture's thumbnail are needs the application answers on worker
threads; a double click on a folder goes into it, on a file opens it with
the system's application for it.

	files               the home folder
	files path          another folder
*/
package main

import "core:os"

import "jm:ui/sdl"

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
	if !app.init(h, sdl.wake) {
		os.exit(1)
	}
	m: view.Model
	view.model_init(&m, path)
	defer view.model_destroy(&m)
	sdl.run({title = "files", width = WIDTH, height = HEIGHT, ui = view.view, user = &m, fonts = common.fonts(), data = app.data_host(h)})
	app.stop(h)
}

