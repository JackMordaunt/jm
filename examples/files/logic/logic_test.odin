package files_logic

import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:testing"

import "../files"

P :: files.path_make

@(private = "file")
plan_of :: proc(effects: ..Effect) -> (p: Plan) {
	for e in effects {
		add(&p, e)
	}
	return
}

@(private = "file")
expect_plan :: proc(t: ^testing.T, name: string, got, want: Plan, loc := #caller_location) {
	got, want := got, want
	same := got.count == want.count
	for ii in 0 ..< min(got.count, want.count) {
		same = same && got.effects[ii] == want.effects[ii]
	}
	testing.expectf(t, same, "%s:\n got  %s\n want %s", name, describe(&got), describe(&want), loc = loc)
}

// describe names each effect, and a report's text, for a failure message.
@(private = "file")
describe :: proc(p: ^Plan) -> string {
	out := ""
	for &e in effects_of(p) {
		if r, ok := &e.(Report); ok {
			out = fmt.tprintf("%s Report(%s)", out, message_of(&r.message))
		} else {
			out = fmt.tprintf("%s %v", out, reflect.union_variant_typeid(e))
		}
	}
	return out
}

@(private = "file")
reported :: proc(p: Plan) -> string {
	p := p
	for &e in effects_of(&p) {
		if r, ok := &e.(Report); ok {
			return message_of(&r.message)
		}
	}
	return ""
}

@(test)
rename_checks_the_name_against_the_folder_and_moves_places :: proc(t: ^testing.T) {
	siblings := []string{"notes.txt", "Photos"}
	ok := Rename_Facts{exists = true, siblings = siblings, on = .Darwin}
	r := files.Rename{P("/d/notes.txt"), files.name_make("todo.txt")}
	expect_plan(t, "a free name", rename(r, ok), plan_of(Rename_Entry{P("/d/notes.txt"), P("/d/todo.txt")}, Journal{{change = .Renamed, a = P("/d/notes.txt"), b = P("/d/todo.txt")}}))
	with_places := ok
	with_places.places_under = true
	expect_plan(t, "pins follow", rename(r, with_places), plan_of(Rename_Entry{P("/d/notes.txt"), P("/d/todo.txt")}, Move_Places{P("/d/notes.txt"), P("/d/todo.txt")}, Journal{{change = .Renamed, a = P("/d/notes.txt"), b = P("/d/todo.txt")}}))
	expect_plan(t, "the same name", rename({P("/d/notes.txt"), files.name_make("notes.txt")}, ok), {})

	taken := files.Rename{P("/d/notes.txt"), files.name_make("photos")}
	testing.expect_value(t, reported(rename(taken, ok)), "There is already an item called “Photos” here.")
	linux := ok
	linux.on = .Linux
	testing.expect_value(t, rename(taken, linux).effects[0].(Rename_Entry).to, P("/d/photos"))
	// A change of case alone is the entry's own name, not a collision.
	expect_plan(t, "a change of case", rename({P("/d/notes.txt"), files.name_make("Notes.txt")}, ok), plan_of(Rename_Entry{P("/d/notes.txt"), P("/d/Notes.txt")}, Journal{{change = .Renamed, a = P("/d/notes.txt"), b = P("/d/Notes.txt")}}))

	testing.expect_value(t, reported(rename({P("/d/notes.txt"), files.name_make("a/b")}, ok)), "“a/b” can't be a name: a name can't hold a path separator.")
	gone := ok
	gone.exists = false
	testing.expect_value(t, reported(rename(r, gone)), "“notes.txt” is no longer there.")
	home := ok
	home.reason = .Home
	testing.expect_value(t, reported(rename(r, home)), "“notes.txt” can't be renamed: it is your home folder.")
}

@(test)
new_folder_takes_the_next_free_name :: proc(t: ^testing.T) {
	f := New_Folder_Facts{parent_is_dir = true, siblings = {"New folder", "new folder 2"}, on = .Darwin}
	c := files.New_Folder{P("/d"), files.name_make("New folder")}
	expect_plan(t, "numbered past both", new_folder(c, f), plan_of(Make_Folder{P("/d/New folder 3")}, Journal{{change = .Created, a = P("/d/New folder 3")}}))
	f.parent_is_dir = false
	testing.expect_value(t, reported(new_folder(c, f)), "“d” is no longer a folder.")
	testing.expect_value(t, reported(new_folder({P("/d"), files.name_make("CON")}, {parent_is_dir = true, on = .Windows})), "“CON” can't be a name: this system keeps that name for a device.")
}

@(test)
trash_refuses_what_is_protected_and_forgets_its_places :: proc(t: ^testing.T) {
	c := files.Trash{P("/d/x")}
	expect_plan(t, "trash", trash(c, {exists = true, places_under = true}), plan_of(Trash_Entry{P("/d/x")}, Forget_Places{P("/d/x")}, Journal{{change = .Trashed, a = P("/d/x")}}))
	testing.expect_value(t, reported(trash(c, {exists = true, reason = .Place})), "“x” can't go to the Trash: your system keeps it there.")
	testing.expect_value(t, reported(trash(c, {})), "“x” is no longer there.")
}

@(test)
paste_goes_by_the_method_placement_gives :: proc(t: ^testing.T) {
	f := Paste_Facts{source_exists = true, dest_is_dir = true, same_volume = true, siblings = {"other"}, on = .Linux}
	move := files.Paste{P("/a/f"), P("/b"), .Move}
	copy_ := files.Paste{P("/a/f"), P("/b"), .Copy}
	expect_plan(t, "move on one volume", paste(move, f), plan_of(Rename_Entry{P("/a/f"), P("/b/f")}, Journal{{change = .Renamed, a = P("/a/f"), b = P("/b/f")}}))
	expect_plan(t, "copy", paste(copy_, f), plan_of(Start_Copy{P("/a/f"), P("/b/f"), false}))
	across := f
	across.same_volume = false
	expect_plan(t, "move across", paste(move, across), plan_of(Start_Copy{P("/a/f"), P("/b/f"), true}))
	expect_plan(t, "move where it is", paste({P("/a/f"), P("/a"), .Move}, f), {})
	dup := f
	dup.siblings = {"f", "f 2"}
	expect_plan(t, "copy where it is", paste({P("/a/f"), P("/a"), .Copy}, dup), plan_of(Start_Copy{P("/a/f"), P("/a/f 3"), false}))
	taken := f
	taken.siblings = {"f"}
	asked := paste(move, taken)
	testing.expect_value(t, asked.count, 1)
	ask, is_ask := asked.effects[0].(Ask)
	testing.expect(t, is_ask)
	testing.expect_value(t, message_of(&ask.question), "“b” already has an item called that.")
	testing.expect_value(t, ask.paste, move)
	folder := f
	folder.source_is_dir = true
	testing.expect_value(t, reported(paste({P("/a"), P("/a/b"), .Move}, folder)), "“a” can't go inside itself.")
	protected := f
	protected.reason = .Place
	testing.expect_value(t, reported(paste(move, protected)), "“f” can't be moved: your system keeps it there.")
	expect_plan(t, "copying a protected folder is fine", paste(copy_, protected), plan_of(Start_Copy{P("/a/f"), P("/b/f"), false}))
}

@(test)
resolve_acts_on_the_facts_as_they_are_now :: proc(t: ^testing.T) {
	move := files.Paste{P("/a/f"), P("/b"), .Move}
	now := Paste_Facts{source_exists = true, dest_is_dir = true, same_volume = true, siblings = {"f"}, on = .Linux}
	f := Resolve_Facts{asking = true, paste = move, now = now}
	expect_plan(t, "skip", resolve({4, .Skip}, f), plan_of(Settle{4}))
	expect_plan(t, "keep both", resolve({4, .Keep_Both}, f), plan_of(Settle{4}, Rename_Entry{P("/a/f"), P("/b/f 2")}, Journal{{change = .Renamed, a = P("/a/f"), b = P("/b/f 2")}}))
	expect_plan(t, "replace", resolve({4, .Replace}, f), plan_of(Settle{4}, Trash_Entry{P("/b/f")}, Rename_Entry{P("/a/f"), P("/b/f")}, Journal{{change = .Renamed, a = P("/a/f"), b = P("/b/f")}}))
	// The one in the way went meanwhile: Replace has nothing to trash.
	freed := f
	freed.now.siblings = {}
	expect_plan(t, "replace, freed", resolve({4, .Replace}, freed), plan_of(Settle{4}, Rename_Entry{P("/a/f"), P("/b/f")}, Journal{{change = .Renamed, a = P("/a/f"), b = P("/b/f")}}))
	gone := f
	gone.now.source_exists = false
	testing.expect_value(t, reported(resolve({4, .Replace}, gone)), "“f” is no longer there.")
	expect_plan(t, "an answer that came too late", resolve({4, .Replace}, {}), {})
}

@(test)
copy_done_finishes_a_move_or_cleans_up :: proc(t: ^testing.T) {
	base := Copy_Done_Facts{op = 7, from = P("/a/f"), to = P("/b/f")}
	ok := base
	ok.ok = true
	expect_plan(t, "a copy", copy_done(ok), plan_of(Settle{7}, Journal{{change = .Copied, a = P("/b/f")}}))
	moved := ok
	moved.then_trash = true
	moved.places_under = true
	expect_plan(t, "a move", copy_done(moved), plan_of(Settle{7}, Trash_Entry{P("/a/f")}, Move_Places{P("/a/f"), P("/b/f")}, Journal{{change = .Moved_Across, a = P("/a/f"), b = P("/b/f")}}))
	cancelled := base
	cancelled.cancelled = true
	cancelled.partial_exists = true
	expect_plan(t, "cancelled", copy_done(cancelled), plan_of(Settle{7}, Trash_Entry{P("/b/f")}))
	failed := base
	failed.error = message("disk full")
	testing.expect_value(t, reported(copy_done(failed)), "“f” couldn't be copied: disk full")
}

@(test)
cancel_stops_a_copy_or_drops_a_question :: proc(t: ^testing.T) {
	expect_plan(t, "running", cancel({3}, {running = true}), plan_of(Stop_Copy{3}))
	expect_plan(t, "asking", cancel({3}, {asking = true}), plan_of(Settle{3}))
	expect_plan(t, "unknown", cancel({3}, {}), {})
}

@(test)
undo_reverses_only_what_the_world_still_matches :: proc(t: ^testing.T) {
	renamed := Record{id = 9, change = .Renamed, a = P("/d/old"), b = P("/d/new")}
	expect_plan(t, "rename", undo({has = true, record = renamed, b_exists = true}), plan_of(Rename_Entry{P("/d/new"), P("/d/old")}, Move_Places{P("/d/new"), P("/d/old")}, Unjournal{9}))
	expect_plan(t, "rename, old name taken", undo({has = true, record = renamed, a_exists = true, b_exists = true}), plan_of(Report{message("“new” has changed since it was renamed.")}, Unjournal{9}))

	created := Record{id = 2, change = .Created, a = P("/d/New folder")}
	expect_plan(t, "empty folder", undo({has = true, record = created, a_exists = true, a_empty = true}), plan_of(Trash_Entry{P("/d/New folder")}, Unjournal{2}))
	testing.expect_value(t, reported(undo({has = true, record = created, a_exists = true})), "“New folder” has things in it now.")
	expect_plan(t, "folder already gone", undo({has = true, record = created}), plan_of(Unjournal{2}))

	trashed := Record{id = 3, change = .Trashed, a = P("/d/x"), b = P("/T/x")}
	expect_plan(t, "trash", undo({has = true, record = trashed, b_exists = true}), plan_of(Restore_Entry{P("/T/x"), P("/d/x")}, Unjournal{3}))
	unknown := Record{id = 3, change = .Trashed, a = P("/d/x")}
	testing.expect_value(t, reported(undo({has = true, record = unknown})), "Restore “x” from the Recycle Bin.")

	moved := Record{id = 5, change = .Moved_Across, a = P("/a/f"), b = P("/v/f"), c = P("/T/f")}
	expect_plan(t, "move across", undo({has = true, record = moved, b_exists = true, c_exists = true}), plan_of(Trash_Entry{P("/v/f")}, Restore_Entry{P("/T/f"), P("/a/f")}, Move_Places{P("/v/f"), P("/a/f")}, Unjournal{5}))
	testing.expect_value(t, reported(undo({})), "There is nothing to undo.")
	label := undo_label(&renamed)
	testing.expect_value(t, message_of(&label), "Undo rename of “old”")
}

@(test)
a_path_cut_short_is_refused_not_acted_on :: proc(t: ^testing.T) {
	long := strings.repeat("x", files.MAX_PATH + 10)
	defer delete(long)
	cut := files.path_make(long)
	want := "That path is longer than 1024 bytes, too long to work with."
	testing.expect_value(t, reported(trash({cut}, {exists = true})), want)
	testing.expect_value(t, reported(rename({cut, files.name_make("n")}, {exists = true})), want)
	testing.expect_value(t, reported(paste({P("/a/f"), cut, .Copy}, {source_exists = true, dest_is_dir = true})), want)
	testing.expect_value(t, reported(open({cut})), want)
	fits := files.path_make(long[:files.MAX_PATH])
	expect_plan(t, "a path of exactly MAX_PATH bytes", open({fits}), plan_of(Open_File{fits}))
}
