/*
gallery is a grid of ten thousand pictures made on demand: a jm application
on the same model as examples/todo, showing work that takes time. A tile
is needed while it is in view; the application makes its picture on a
worker thread and delivers it; a tile scrolled away before its picture is
done is abandoned, and the header counts both. Pictures are written under
the temp directory, in a folder for this run.

	gallery
*/
package main

import "core:os"

import "jm:ui/sdl"

import "../common"
import "app"
import "view"

WIDTH :: 720
HEIGHT :: 760

main :: proc() {
	h := new(app.Host)
	defer free(h)
	if !app.init(h, sdl.wake) {
		os.exit(1)
	}
	m: view.Model
	sdl.run({title = "gallery", width = WIDTH, height = HEIGHT, ui = view.view, user = &m, fonts = common.fonts(), data = app.data_host(h)})
	app.stop(h)
}

