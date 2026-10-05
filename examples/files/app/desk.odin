package files_app

import "core:encoding/cbor"
import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:sync"
import "core:time"

import "jm:sqlite3"
import "jm:stream"
import "jm:ui"

import "../../common"
import "../files"
import "../fs"
import "../logic"
import "../naming"
import "../protection"
import "../query"
import "../store"

MAX_PROBLEMS :: 8
MAX_OPS :: 8
PROGRESS_EVERY :: 100 * time.Millisecond

// Read asks the desk for a sidebar list or the activity, under key.
Read :: struct {
	key:  ui.Need_Key,
	kind: Read_Kind,
}

Read_Kind :: enum u8 {
	Recent,
	Pins,
	Activity,
}

// Copy_Event is a copy's progress, or its end, as its worker reports it.
Copy_Event :: struct {
	op:       u64,
	done:     i64,
	total:    i64,
	finished: bool,
	err:      fs.Error,
}

Desk_In :: union {
	files.Command,
	Read,
	Copy_Event,
}

// Copy_Job is a copy running on the copier thread; the desk owns it and
// frees it when its end comes back.
Copy_Job :: struct {
	h:          ^Host,
	op:         u64,
	from, to:   files.Path,
	then_trash: bool,
	cancel:     bool, // atomic
	reported:   time.Tick, // when progress was last sent
}

Problem_Slot :: struct {
	id:      u64,
	message: logic.Message,
}

Op_Slot :: struct {
	id:       u64,
	label:    logic.Message,
	done:     i64,
	total:    i64,
	asking:   bool,
	question: logic.Message,
	paste:    files.Paste, // what an asking operation asked about
	copy:     ^Copy_Job, // a running copy's job, else nil
}

// Desk is the stage pinned to the store's thread. Every command is
// enriched, planned by logic and executed here, one at a time, so the
// facts a plan was made from cannot change under the store's half of
// it; the filesystem's half is guarded by primitives that fail rather
// than replace (see fs.rename_noreplace).
Desk :: struct {
	h:            ^Host,
	store:        store.Store,
	allocator:    mem.Allocator, // the results' bytes
	out:          [dynamic]common.Result,
	problems:     [MAX_PROBLEMS]Problem_Slot,
	problem_n:    int,
	ops:          [MAX_OPS]Op_Slot,
	op_n:         int,
	next_id:      u64, // for problems and operations
}

// desk_apply is the stage: a command runs, a read is answered, a copy's
// event is taken in. It is the f of a stream.flat_map_with, so the slice
// it returns lives until the next call; each result's bytes are the
// sink's to free.
desk_apply :: proc(d: ^Desk, v: Desk_In) -> []common.Result {
	clear(&d.out)
	switch v in v {
	case files.Command:
		run(d, v)
		put_activity(d)
	case Read:
		answer(d, v)
	case Copy_Event:
		take_copy_event(d, v)
	}
	return d.out[:]
}

// run gathers what the command's flow needs, has logic plan it, and
// carries the plan out.
@(private)
run :: proc(d: ^Desk, c: files.Command) {
	p: logic.Plan
	switch v in c {
	case files.Open:
		p = logic.open(v)
	case files.Visited:
		p = logic.visited(v)
	case files.Pin:
		p = logic.pin(v)
	case files.Unpin:
		p = logic.unpin(v)
	case files.Dismiss:
		p = logic.dismiss(v)
	case files.Rename:
		p = logic.rename(v, rename_facts(d, v))
	case files.New_Folder:
		p = logic.new_folder(v, new_folder_facts(v))
	case files.Trash:
		p = logic.trash(v, trash_facts(d, v))
	case files.Paste:
		p = logic.paste(v, paste_facts(d, v))
	case files.Resolve:
		p = logic.resolve(v, resolve_facts(d, v))
	case files.Cancel:
		p = logic.cancel(v, cancel_facts(d, v))
	case files.Undo:
		p = logic.undo(undo_facts(d))
	}
	execute(d, &p)
}

// --- enrich: the facts each flow reads ---------------------------------------

@(private)
rename_facts :: proc(d: ^Desk, c: files.Rename) -> logic.Rename_Facts {
	c := c
	path := files.path_of(&c.path)
	return {
		exists = fs.info(path).exists,
		reason = protection.reason(path, d.h.home, d.h.place_paths),
		siblings = fs.names(filepath.dir(path), context.temp_allocator),
		places_under = places_under(d, path),
		on = naming.HOST,
	}
}

@(private)
new_folder_facts :: proc(c: files.New_Folder) -> logic.New_Folder_Facts {
	c := c
	parent := files.path_of(&c.parent)
	return {parent_is_dir = fs.info(parent).is_dir, siblings = fs.names(parent, context.temp_allocator), on = naming.HOST}
}

@(private)
trash_facts :: proc(d: ^Desk, c: files.Trash) -> logic.Trash_Facts {
	c := c
	path := files.path_of(&c.path)
	return {exists = fs.info(path).exists, reason = protection.reason(path, d.h.home, d.h.place_paths), places_under = places_under(d, path)}
}

@(private)
paste_facts :: proc(d: ^Desk, c: files.Paste) -> logic.Paste_Facts {
	c := c
	source := files.path_of(&c.source)
	dest := files.path_of(&c.dest)
	si, di := fs.info(source), fs.info(dest)
	return {
		source_exists = si.exists,
		source_is_dir = si.is_dir,
		dest_is_dir = di.is_dir,
		same_volume = si.exists && di.exists && si.volume == di.volume,
		reason = protection.reason(source, d.h.home, d.h.place_paths),
		siblings = fs.names(dest, context.temp_allocator),
		places_under = places_under(d, source),
		on = naming.HOST,
	}
}

@(private)
resolve_facts :: proc(d: ^Desk, c: files.Resolve) -> logic.Resolve_Facts {
	op := find_op(d, c.op)
	if op == nil || !op.asking {
		return {}
	}
	return {asking = true, paste = op.paste, now = paste_facts(d, op.paste)}
}

@(private)
cancel_facts :: proc(d: ^Desk, c: files.Cancel) -> logic.Cancel_Facts {
	op := find_op(d, c.op)
	if op == nil {
		return {}
	}
	return {running = op.copy != nil, asking = op.asking}
}

@(private)
undo_facts :: proc(d: ^Desk) -> (f: logic.Undo_Facts) {
	f.record, f.has = newest(d)
	if !f.has {
		return
	}
	e := &f.record
	f.a_exists = e.a.len > 0 && fs.info(files.path_of(&e.a)).exists
	f.b_exists = e.b.len > 0 && fs.info(files.path_of(&e.b)).exists
	f.c_exists = e.c.len > 0 && fs.info(files.path_of(&e.c)).exists
	f.a_empty = f.a_exists && fs.is_empty(files.path_of(&e.a))
	return
}

// newest is the journal's newest change as logic's Entry.
@(private)
newest :: proc(d: ^Desk) -> (e: logic.Record, has: bool) {
	row, ok, err := store.newest(&d.store)
	if err != nil {
		fmt.eprintln("files: journal:", err)
		return
	}
	if !ok {
		return
	}
	return {id = row.id, change = logic.Change(row.change), a = files.path_make(row.a), b = files.path_make(row.b), c = files.path_make(row.c)}, true
}

@(private)
places_under :: proc(d: ^Desk, path: string) -> bool {
	yes, err := store.places_under(&d.store, path)
	if err != nil {
		fmt.eprintln("files: places:", err)
	}
	return yes
}

// --- execute: the plan, in its three groups -------------------------------------

@(private)
Execution :: struct {
	trashed: files.Path, // where the plan's last Trash_Entry put its entry
	changed: [MAX_EFFECTS * 2]files.Path, // folders whose listings changed
	changed_n: int,
	fs_done: bool, // a filesystem effect happened
}

@(private)
MAX_EFFECTS :: logic.MAX_EFFECTS

// execute carries the plan out: the filesystem's effects one at a time,
// stopping at the first to fail; the store's in one transaction; then
// the memory's. Nothing here looks inside an effect to decide anything.
@(private)
execute :: proc(d: ^Desk, p: ^logic.Plan) {
	so_far: Execution
	effects := logic.effects_of(p)
	for &e in effects {
		if !execute_fs(d, &e, &so_far) {
			relist_changed(d, &so_far)
			return
		}
	}
	if err := execute_store(d, effects, &so_far); err != nil {
		fmt.eprintln("files: store:", err)
		if so_far.fs_done {
			report(d, "The change was made, but the sidebar and Undo could not record it.")
		} else {
			report(d, "That could not be saved.")
		}
	}
	for &e in effects {
		execute_memory(d, &e)
	}
	relist_changed(d, &so_far)
}

// execute_fs carries out e if it is the filesystem's, reporting a
// failure and returning false so the rest of the plan is dropped.
@(private)
execute_fs :: proc(d: ^Desk, e: ^logic.Effect, so_far: ^Execution) -> bool {
	err := fs.Error.None
	what: string
	switch &v in e {
	case logic.Rename_Entry:
		from, to := files.path_of(&v.from), files.path_of(&v.to)
		err = fs.rename_noreplace(from, to)
		what = fmt.tprintf("“%s” couldn't be renamed", filepath.base(from))
		note_changed(so_far, filepath.dir(from))
		note_changed(so_far, filepath.dir(to))
	case logic.Make_Folder:
		path := files.path_of(&v.path)
		err = fs.make_folder(path)
		what = fmt.tprintf("The folder “%s” couldn't be made", filepath.base(path))
		note_changed(so_far, filepath.dir(path))
	case logic.Trash_Entry:
		path := files.path_of(&v.path)
		trashed: string
		trashed, err = fs.trash(path, context.temp_allocator)
		so_far.trashed = files.path_make(trashed)
		what = fmt.tprintf("“%s” couldn't go to the Trash", filepath.base(path))
		note_changed(so_far, filepath.dir(path))
	case logic.Restore_Entry:
		to := files.path_of(&v.to)
		err = fs.restore(files.path_of(&v.trashed), to)
		what = fmt.tprintf("“%s” couldn't be put back", filepath.base(to))
		note_changed(so_far, filepath.dir(to))
	case logic.Start_Copy:
		start_copy(d, v)
	case logic.Open_File:
		open_file(d.h, files.path_of(&v.path))
	case logic.Record_Visit, logic.Add_Pin, logic.Remove_Pin, logic.Move_Places, logic.Forget_Places, logic.Journal, logic.Unjournal:
		return true // the store's
	case logic.Report, logic.Withdraw, logic.Ask, logic.Settle, logic.Stop_Copy:
		return true // the memory's
	}
	if err != .None {
		report(d, "%s: %s", what, fs.describe(err))
		return false
	}
	so_far.fs_done = true
	return true
}

// execute_store carries out the store's effects in one transaction, and
// opens none if there are none.
@(private)
execute_store :: proc(d: ^Desk, effects: []logic.Effect, so_far: ^Execution) -> sqlite3.Error {
	n := 0
	for &e in effects {
		if is_store(&e) {
			n += 1
		}
	}
	if n == 0 {
		return nil
	}
	st := &d.store
	store.begin(st) or_return
	for &e in effects {
		if err := execute_store_effect(st, &e, so_far); err != nil {
			store.rollback(st)
			return err
		}
	}
	return store.commit(st)
}

@(private)
is_store :: proc(e: ^logic.Effect) -> bool {
	switch _ in e {
	case logic.Record_Visit, logic.Add_Pin, logic.Remove_Pin, logic.Move_Places, logic.Forget_Places, logic.Journal, logic.Unjournal:
		return true
	case logic.Rename_Entry, logic.Make_Folder, logic.Trash_Entry, logic.Restore_Entry, logic.Start_Copy, logic.Open_File:
	case logic.Report, logic.Withdraw, logic.Ask, logic.Settle, logic.Stop_Copy:
	}
	return false
}

@(private)
execute_store_effect :: proc(st: ^store.Store, e: ^logic.Effect, so_far: ^Execution) -> sqlite3.Error {
	switch &v in e {
	case logic.Record_Visit:
		return store.visit(st, files.path_of(&v.path), files.name_of(&v.name), v.dir)
	case logic.Add_Pin:
		return store.pin(st, files.path_of(&v.path), files.name_of(&v.name))
	case logic.Remove_Pin:
		return store.unpin(st, files.path_of(&v.path))
	case logic.Move_Places:
		return store.move_places(st, files.path_of(&v.from), files.path_of(&v.to))
	case logic.Forget_Places:
		return store.forget_places(st, files.path_of(&v.path))
	case logic.Journal:
		// A trash's record takes the path the Trash produced.
		en := v.record
		if en.change == .Trashed && en.b.len == 0 {
			en.b = so_far.trashed
		} else if en.change == .Moved_Across && en.c.len == 0 {
			en.c = so_far.trashed
		}
		return store.journal(st, u8(en.change), files.path_of(&en.a), files.path_of(&en.b), files.path_of(&en.c))
	case logic.Unjournal:
		return store.unjournal(st, v.id)
	case logic.Rename_Entry, logic.Make_Folder, logic.Trash_Entry, logic.Restore_Entry, logic.Start_Copy, logic.Open_File:
	case logic.Report, logic.Withdraw, logic.Ask, logic.Settle, logic.Stop_Copy:
	}
	return nil
}

@(private)
execute_memory :: proc(d: ^Desk, e: ^logic.Effect) {
	switch &v in e {
	case logic.Report:
		report(d, "%s", logic.message_of(&v.message))
	case logic.Withdraw:
		withdraw(d, v.id)
	case logic.Ask:
		if op := new_op(d); op != nil {
			op.asking = true
			op.question = v.question
			op.paste = v.paste
			op.label = logic.message("%s “%s”", "Moving" if v.paste.mode == .Move else "Copying", filepath.base(files.path_of(&op.paste.source)))
		}
	case logic.Settle:
		settle(d, v.op)
	case logic.Stop_Copy:
		if op := find_op(d, v.op); op != nil && op.copy != nil {
			sync.atomic_store(&op.copy.cancel, true)
		}
	case logic.Rename_Entry, logic.Make_Folder, logic.Trash_Entry, logic.Restore_Entry, logic.Start_Copy, logic.Open_File:
	case logic.Record_Visit, logic.Add_Pin, logic.Remove_Pin, logic.Move_Places, logic.Forget_Places, logic.Journal, logic.Unjournal:
	}
}

@(private)
note_changed :: proc(so_far: ^Execution, folder: string) {
	if so_far.changed_n < len(so_far.changed) {
		so_far.changed[so_far.changed_n] = files.path_make(folder)
		so_far.changed_n += 1
	}
}

@(private)
relist_changed :: proc(d: ^Desk, so_far: ^Execution) {
	for &p in so_far.changed[:so_far.changed_n] {
		relist(d.h, files.path_of(&p))
	}
}

// --- copies ---------------------------------------------------------------------

// start_copy makes the copy an operation and hands it to the copier.
@(private)
start_copy :: proc(d: ^Desk, v: logic.Start_Copy) {
	v := v
	op := new_op(d)
	if op == nil {
		report(d, "Too much is happening at once; try again when a copy finishes.")
		return
	}
	from, to := files.path_of(&v.from), files.path_of(&v.to)
	op.label = logic.message("%s “%s” to “%s”", "Moving" if v.then_trash else "Copying", filepath.base(from), filepath.base(filepath.dir(to)))
	job := new(Copy_Job, d.h.allocator)
	job^ = {h = d.h, op = op.id, from = v.from, to = v.to, then_trash = v.then_trash}
	op.copy = job
	stream.submit(d.h.copiers, copy_main, job)
}

// copy_main runs on the copier thread: the copy, progress at most every
// PROGRESS_EVERY, and its end, back to the desk through a port.
@(private)
copy_main :: proc(data: rawptr) {
	job := (^Copy_Job)(data)
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, job.h.allocator, job.h.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)
	job.reported = time.tick_now()
	err := fs.copy_tree(files.path_of(&job.from), files.path_of(&job.to), &job.cancel, proc(user: rawptr, done, total: i64) {
			job := (^Copy_Job)(user)
			if done > 0 && done < total && time.tick_since(job.reported) < PROGRESS_EVERY {
				return
			}
			job.reported = time.tick_now()
			stream.port_push(job.h.copy_events, Copy_Event{op = job.op, done = done, total = total})
		}, job)
	stream.port_send(job.h.copy_events, Copy_Event{op = job.op, finished = true, err = err})
}

// take_copy_event takes a copy's progress, or ends its operation with
// the plan logic makes of how it went.
@(private)
take_copy_event :: proc(d: ^Desk, e: Copy_Event) {
	op := find_op(d, e.op)
	if op == nil || op.copy == nil {
		return
	}
	if !e.finished {
		op.done, op.total = e.done, e.total
		put_activity(d)
		return
	}
	job := op.copy
	op.copy = nil
	to := files.path_of(&job.to)
	f := logic.Copy_Done_Facts {
		op = op.id,
		from = job.from,
		to = job.to,
		then_trash = job.then_trash,
		ok = e.err == .None,
		cancelled = e.err == .Cancelled,
		error = logic.message("%s", fs.describe(e.err)),
		partial_exists = e.err != .Exists && fs.info(to).exists,
		places_under = places_under(d, files.path_of(&job.from)),
	}
	free(job, d.h.allocator)
	p := logic.copy_done(f)
	execute(d, &p)
	relist(d.h, filepath.dir(to))
	put_activity(d)
}

// --- memory: problems and operations -----------------------------------------------

@(private)
report :: proc(d: ^Desk, format: string, args: ..any) {
	if d.problem_n == MAX_PROBLEMS {
		copy(d.problems[:], d.problems[1:])
		d.problem_n -= 1
	}
	d.next_id += 1
	d.problems[d.problem_n] = {d.next_id, logic.message(format, ..args)}
	d.problem_n += 1
}

@(private)
withdraw :: proc(d: ^Desk, id: u64) {
	for ii in 0 ..< d.problem_n {
		if d.problems[ii].id == id {
			copy(d.problems[ii:], d.problems[ii + 1:d.problem_n])
			d.problem_n -= 1
			return
		}
	}
}

@(private)
new_op :: proc(d: ^Desk) -> ^Op_Slot {
	if d.op_n == MAX_OPS {
		return nil
	}
	d.next_id += 1
	op := &d.ops[d.op_n]
	op^ = {id = d.next_id}
	d.op_n += 1
	return op
}

@(private)
find_op :: proc(d: ^Desk, id: u64) -> ^Op_Slot {
	for &op in d.ops[:d.op_n] {
		if op.id == id {
			return &op
		}
	}
	return nil
}

// settle ends an operation; a copy still running is not settled, since
// its end must come back to be cleared up.
@(private)
settle :: proc(d: ^Desk, id: u64) {
	for ii in 0 ..< d.op_n {
		if d.ops[ii].id == id && d.ops[ii].copy == nil {
			copy(d.ops[ii:], d.ops[ii + 1:d.op_n])
			d.op_n -= 1
			return
		}
	}
}

// --- reads ----------------------------------------------------------------------

@(private)
answer :: proc(d: ^Desk, r: Read) {
	switch r.kind {
	case .Recent:
		items, err := store.recent(&d.store)
		if err == nil {
			put(d, r.key, query.Recent_Places_Result{items = items})
		}
	case .Pins:
		items, err := store.pins(&d.store)
		if err == nil {
			put(d, r.key, query.Pins_Result{items = items})
		}
	case .Activity:
		put_activity(d, r.key)
	}
}

// put_activity delivers the activity: the operations, the problems and
// what Undo would undo.
@(private)
put_activity :: proc(d: ^Desk, key := ui.Need_Key(0)) {
	key := key if key != 0 else ui.key_of(query.Activity{})
	ops := make([]query.Operation, d.op_n, context.temp_allocator)
	for &op, ii in d.ops[:d.op_n] {
		ops[ii] = {id = op.id, label = logic.message_of(&op.label), done = op.done, total = op.total, question = logic.message_of(&op.question) if op.asking else ""}
	}
	problems := make([]query.Problem, d.problem_n, context.temp_allocator)
	for &p, ii in d.problems[:d.problem_n] {
		problems[ii] = {id = p.id, message = logic.message_of(&p.message)}
	}
	undo: string
	if e, has := newest(d); has {
		label := logic.undo_label(&e)
		undo = fmt.tprintf("%s", logic.message_of(&label))
	}
	put(d, key, query.Activity_Result{operations = ops, problems = problems, undo = undo})
}

@(private)
put :: proc(d: ^Desk, key: ui.Need_Key, v: $T) {
	bytes, err := cbor.marshal_into_bytes(v, allocator = d.allocator, temp_allocator = context.temp_allocator)
	if err != nil {
		fmt.eprintln("files: marshal:", err)
		return
	}
	append(&d.out, common.Result{key, bytes})
}
