package files_app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:sqlite3"
import "jm:ui"

import "../files"
import "../fs"
import "../logic"
import "../store"

// The desk alone, on this thread: a store in memory and a host with no
// pipeline, enough for execute to run a plan and relist nothing.
@(private = "file")
Bench :: struct {
	h: Host,
}

@(private = "file")
bench_open :: proc(t: ^testing.T, b: ^Bench) {
	b.h.allocator = context.allocator
	b.h.listings = make(map[ui.Need_Key]Shown_Folder)
	b.h.desk.h = &b.h
	b.h.desk.allocator = context.allocator
	testing.expect(t, store.open(&b.h.desk.store, sqlite3.MEMORY, nil, nil))
}

@(private = "file")
bench_close :: proc(b: ^Bench) {
	store.close(&b.h.desk.store)
	delete(b.h.listings)
	delete(b.h.desk.out)
}

@(private = "file")
scratch :: proc(name: string) -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, fmt.tprintf("jm-files-desk-%s-%d", name, time.now()._nsec)}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	return dir
}

// The plan was made when the name was free; by the time it runs,
// something has taken it. The rename's primitive refuses, and the rest
// of the plan, the journal entry here, is dropped: Undo never hears of a
// change that did not happen.
@(test)
a_failed_filesystem_effect_drops_the_rest_of_the_plan :: proc(t: ^testing.T) {
	b: Bench
	bench_open(t, &b)
	defer bench_close(&b)
	dir := scratch("race")
	defer os.remove_all(dir)
	a, _ := filepath.join({dir, "a"}, context.temp_allocator)
	to, _ := filepath.join({dir, "b"}, context.temp_allocator)
	_ = os.write_entire_file(a, "mine")
	_ = os.write_entire_file(to, "theirs")
	p: logic.Plan
	logic.add(&p, logic.Rename_Entry{files.path_make(a), files.path_make(to)})
	logic.add(&p, logic.Journal{{change = .Renamed, a = files.path_make(a), b = files.path_make(to)}})
	execute(&b.h.desk, &p)
	d := &b.h.desk
	testing.expect_value(t, d.problem_n, 1)
	testing.expect_value(t, logic.message_of(&d.problems[0].message), "“a” couldn't be renamed: something by that name is there now.")
	_, has, _ := store.newest(&d.store)
	testing.expect(t, !has, "nothing was journalled")
	theirs, _ := os.read_entire_file(to, context.temp_allocator)
	testing.expect_value(t, string(theirs), "theirs")
}

// A trash's journal entry is written with the path the Trash gave back,
// which only the trash's execution knows.
@(test)
a_trashs_journal_entry_takes_the_trashs_path :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return // the Recycle Bin gives no path back
	}
	b: Bench
	bench_open(t, &b)
	defer bench_close(&b)
	dir := scratch("trash")
	defer os.remove_all(dir)
	f, _ := filepath.join({dir, "jm-files-desk-trash.txt"}, context.temp_allocator)
	_ = os.write_entire_file(f, "x")
	p: logic.Plan
	logic.add(&p, logic.Trash_Entry{files.path_make(f)})
	logic.add(&p, logic.Journal{{change = .Trashed, a = files.path_make(f)}})
	execute(&b.h.desk, &p)
	row, has, _ := store.newest(&b.h.desk.store)
	testing.expect(t, has)
	testing.expect(t, row.b != "" && strings.contains(row.b, "jm-files-desk-trash"), "the entry names where the Trash put it")
	testing.expect_value(t, fs.restore(row.b, f), fs.Error.None)
}
