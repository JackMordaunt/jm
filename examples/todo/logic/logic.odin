/*
Package logic is the todo application's rules: what each command means,
what makes one invalid, and what the store should do about a valid one. It
is pure. A request comes in, an outcome goes out, and the outcome is either
a write for the store, a problem for the problem list, or nothing. It holds
no database and no ui, so it is tested by calling process.

Messages are values with fixed buffers, not strings, because they cross
stream edges by copy between threads: a Text is as long as the longest
title the rules allow.
*/
package todo_logic

import "core:strings"

import "jm:ui"

import "../shapes"

// MAX_TITLE is the longest title the rules allow, in bytes.
MAX_TITLE :: 120

// Text is a string that fits in a message.
Text :: struct {
	buf: [MAX_TITLE]u8,
	len: int,
}

text_make :: proc(s: string) -> (t: Text) {
	t.len = copy(t.buf[:], s)
	return
}

text_of :: proc(t: ^Text) -> string {
	return string(t.buf[:t.len])
}

// Request is one command as the pipeline carries it: decoded from the
// ui's bytes by whoever runs the frame loop, with the title copied in.
Request :: struct {
	kind:    Kind,
	id:      i64, // Toggle, Edit, Delete: the todo
	done:    bool, // Toggle_All
	problem: u64, // Dismiss
	title:   Text, // Add, Edit
}

Kind :: enum u8 {
	Add,
	Toggle,
	Toggle_All,
	Edit,
	Delete,
	Clear_Completed,
	Dismiss,
}

// Write is what the store does for a valid request.
Write :: struct {
	op:    Op,
	id:    i64,
	done:  bool,
	title: Text,
}

Op :: enum u8 {
	Insert, // title
	Set_Done, // id, done
	Set_All, // done
	Set_Title, // id, title
	Remove, // id
	Remove_Done,
}

// Problem_Event adds a problem to the list, or removes one.
Problem_Event :: struct {
	add:     bool,
	id:      u64,
	message: Text,
}

// Outcome is what a request came to: at most one write and one problem.
Outcome :: struct {
	write:       Write,
	has_write:   bool,
	problem:     Problem_Event,
	has_problem: bool,
}

// Logic is the rules' only state: where problem ids come from.
Logic :: struct {
	next_problem: u64,
}

// request turns a ui command into a Request, if c is one of the contract's
// commands. The title is copied, so c may go.
request :: proc(c: ui.Command) -> (r: Request, ok: bool) {
	if v, is := ui.command_as(c, shapes.Add); is {
		return {kind = .Add, title = text_make(v.title)}, true
	}
	if v, is := ui.command_as(c, shapes.Toggle); is {
		return {kind = .Toggle, id = v.id}, true
	}
	if v, is := ui.command_as(c, shapes.Toggle_All); is {
		return {kind = .Toggle_All, done = v.done}, true
	}
	if v, is := ui.command_as(c, shapes.Edit); is {
		return {kind = .Edit, id = v.id, title = text_make(v.title)}, true
	}
	if v, is := ui.command_as(c, shapes.Delete); is {
		return {kind = .Delete, id = v.id}, true
	}
	if ui.command_is(c, shapes.Clear_Completed) {
		return {kind = .Clear_Completed}, true
	}
	if v, is := ui.command_as(c, shapes.Dismiss); is {
		return {kind = .Dismiss, problem = v.id}, true
	}
	return {}, false
}

// process applies the rules to one request. It runs on the application's
// thread, one request at a time, in the order they were made.
process :: proc(l: ^Logic, r: Request) -> (out: Outcome) {
	r := r
	switch r.kind {
	case .Add:
		title, problem := valid_title(&r.title)
		if problem != "" {
			return refuse(l, problem)
		}
		return write({op = .Insert, title = text_make(title)})
	case .Edit:
		title, problem := valid_title(&r.title)
		if title == "" {
			// TodoMVC: an edit that leaves nothing removes the todo.
			return write({op = .Remove, id = r.id})
		}
		if problem != "" {
			return refuse(l, problem)
		}
		return write({op = .Set_Title, id = r.id, title = text_make(title)})
	case .Toggle:
		// The store flips it: the rules do not know the row's state, and
		// a stale copy in the ui must not decide it.
		return write({op = .Set_Done, id = r.id})
	case .Toggle_All:
		return write({op = .Set_All, done = r.done})
	case .Delete:
		return write({op = .Remove, id = r.id})
	case .Clear_Completed:
		return write({op = .Remove_Done})
	case .Dismiss:
		out.has_problem = true
		out.problem = {add = false, id = r.problem}
		return out
	}
	return out
}

// valid_title trims t and says what is wrong with it, if anything. An
// empty title is not a problem here: Add refuses it, Edit deletes.
@(private)
valid_title :: proc(t: ^Text) -> (title, problem: string) {
	title = strings.trim_space(text_of(t))
	if title == "" {
		return "", "A todo needs a title."
	}
	if t.len == MAX_TITLE {
		return title, "That title is too long to keep."
	}
	return title, ""
}

@(private)
write :: proc(w: Write) -> Outcome {
	return {write = w, has_write = true}
}

@(private)
refuse :: proc(l: ^Logic, message: string) -> Outcome {
	l.next_problem += 1
	return {has_problem = true, problem = {add = true, id = l.next_problem, message = text_make(message)}}
}
