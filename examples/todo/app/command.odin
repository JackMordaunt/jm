package todo_app

import "core:encoding/cbor"
import "core:fmt"
import "core:mem"

import "jm:sqlite3"
import "jm:ui"

import "../../common"
import "../logic"
import "../query"
import "../store"
import "../todo"

MAX_PROBLEMS :: 8

// SAVE_FAILED is the problem a command becomes when the database refuses
// it; the reason goes to the log.
SAVE_FAILED :: "That change could not be saved."

// Read asks a query, to be answered under key.
Read :: struct {
	key: ui.Need_Key,
	q:   Read_Query,
}

Read_Query :: union {
	query.Todos,
	query.Problems,
}

// Db_In is what reaches the store's stage.
Db_In :: union {
	todo.Command,
	Read,
}

Problem_Slot :: struct {
	id:      u64,
	message: todo.Text,
}

// Problem_List is the problems, in memory: nothing about them is stored.
Problem_List :: struct {
	items: [MAX_PROBLEMS]Problem_Slot,
	count: int,
	next:  u64, // the id the next problem gets, less one
}

// Db_Stage is the stage pinned to the store's thread: every command is
// enriched, decided and executed here, in one transaction, so no write
// lands between the facts a decision read and the effect it came to.
Db_Stage :: struct {
	store:     store.Store,
	problems:  Problem_List,
	allocator: mem.Allocator, // the results' bytes
	out:       [dynamic]common.Result, // apply's answer, until the stage has emitted it
}

// db_apply is the stage: a command changes the world, a read is answered.
// It is the f of a stream.flat_map_with, so the slice it returns lives
// until the next call; each result's bytes are the sink's to free.
db_apply :: proc(s: ^Db_Stage, v: Db_In) -> []common.Result {
	clear(&s.out)
	switch v in v {
	case todo.Command:
		run(s, v)
	case Read:
		answer(s, v)
	}
	return s.out[:]
}

// run carries one command through: gather its facts, decide its effect,
// execute that, and commit, or roll back and report the failure.
@(private)
run :: proc(s: ^Db_Stage, c: todo.Command) {
	st := &s.store
	if err := store.begin(st); err != nil {
		fail(s, "begin", err)
		return
	}
	facts, err := enrich(st, c)
	if err == nil {
		err = execute(s, logic.effect(c, facts))
	}
	if err == nil {
		err = store.commit(st)
	}
	if err != nil {
		store.rollback(st)
		fail(s, "command", err)
	}
}

// enrich reads the facts c needs and the ui could not give.
@(private)
enrich :: proc(st: ^store.Store, c: todo.Command) -> (f: logic.Facts, err: sqlite3.Error) {
	switch v in c {
	case todo.Toggle:
		f.exists, f.done = store.todo_state(st, v.id) or_return
	case todo.Edit:
		f.exists, _ = store.todo_state(st, v.id) or_return
	case todo.Toggle_All:
		f.active, _ = store.counts(st) or_return
	case todo.Add, todo.Delete, todo.Clear_Completed, todo.Dismiss:
	}
	return
}

// execute carries out an effect as given. Nothing here looks inside one to
// decide anything: that is logic's.
@(private)
execute :: proc(s: ^Db_Stage, e: logic.Effect) -> sqlite3.Error {
	st := &s.store
	e := e
	switch &v in e {
	case logic.Insert:
		return store.insert(st, todo.text_of(&v.title))
	case logic.Set_Done:
		return store.set_done(st, v.id, v.done)
	case logic.Set_All:
		return store.set_all(st, v.done)
	case logic.Set_Title:
		return store.set_title(st, v.id, todo.text_of(&v.title))
	case logic.Remove:
		return store.remove(st, v.id)
	case logic.Remove_Done:
		return store.remove_done(st)
	case logic.Report:
		report(s, v.message)
	case logic.Withdraw:
		withdraw(s, v.id)
	}
	return nil
}

@(private)
fail :: proc(s: ^Db_Stage, what: string, err: sqlite3.Error) {
	fmt.eprintln("todo:", what, err)
	report(s, SAVE_FAILED)
}

// answer runs a read and marshals its result. Problems are answered from
// memory, so a need mounted after the last change still gets the list.
@(private)
answer :: proc(s: ^Db_Stage, r: Read) {
	switch q in r.q {
	case query.Todos:
		res, err := store.todos(&s.store, q.filter)
		if err != nil {
			fmt.eprintln("todo: read:", err)
			return
		}
		put(s, r.key, res)
	case query.Problems:
		put_problems(s, r.key)
	}
}

// report adds a problem, last; the oldest goes when the list is full.
@(private)
report :: proc(s: ^Db_Stage, message: string) {
	l := &s.problems
	if l.count == MAX_PROBLEMS {
		copy(l.items[:], l.items[1:])
		l.count -= 1
	}
	l.next += 1
	l.items[l.count] = {l.next, todo.text_make(message)}
	l.count += 1
	put_problems(s, ui.key_of(query.Problems{}))
}

@(private)
withdraw :: proc(s: ^Db_Stage, id: u64) {
	l := &s.problems
	for ii in 0 ..< l.count {
		if l.items[ii].id == id {
			copy(l.items[ii:], l.items[ii + 1:l.count])
			l.count -= 1
			put_problems(s, ui.key_of(query.Problems{}))
			return
		}
	}
}

@(private)
put_problems :: proc(s: ^Db_Stage, key: ui.Need_Key) {
	l := &s.problems
	items: [MAX_PROBLEMS]query.Problem
	for ii in 0 ..< l.count {
		items[ii] = {l.items[ii].id, todo.text_of(&l.items[ii].message)}
	}
	put(s, key, query.Problems_Result{items = items[:l.count]})
}

@(private)
put :: proc(s: ^Db_Stage, key: ui.Need_Key, v: $T) {
	bytes, err := cbor.marshal_into_bytes(v, allocator = s.allocator, temp_allocator = context.temp_allocator)
	if err != nil {
		fmt.eprintln("todo: marshal:", err)
		return
	}
	append(&s.out, common.Result{key, bytes})
}
