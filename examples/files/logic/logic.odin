/*
Package logic is the file browser's business processes: for each command,
given the facts the host gathered for it, the domains' decisions and the
effects they come to. It is pure. It reads nothing, writes nothing and
keeps nothing, so it is tested by calling its flows.

Each command has its flow and each flow its own facts, so the compiler
holds the host to gathering what a flow reads:

	enrich   the host reads the facts, from the filesystem and the store
	decide   naming, placement and protection judge
	plan     a flow here maps command, facts and verdicts to a Plan
	execute  the host carries the plan out, in the order the effects say

The effects fall in three groups, which the host carries out in this
order: the filesystem's, one at a time, the first to fail stopping the
plan; then the store's, together in one transaction; then the
application's memory. A filesystem change cannot share the store's
transaction, so it goes first, and the store records only what happened.
*/
package files_logic

import "core:fmt"
import "core:path/filepath"
import "core:strings"

import "../files"
import "../naming"
import "../placement"
import "../protection"

MAX_EFFECTS :: 8
MESSAGE_BYTES :: 400

// Message is text for the ui that fits in a plan.
Message :: struct {
	buf: [MESSAGE_BYTES]u8,
	len: int,
}

message :: proc(format: string, args: ..any) -> (m: Message) {
	m.len = len(fmt.bprintf(m.buf[:], format, ..args))
	return
}

message_of :: proc(m: ^Message) -> string {
	return string(m.buf[:m.len])
}

// Change is a kind of change Undo can reverse.
Change :: enum u8 {
	Renamed, // a from b to: a rename, or a move on one filesystem
	Created, // a the folder made
	Trashed, // a where it was, b where the Trash put it ("" when the system does not say)
	Copied, // a the copy made
	Moved_Across, // a from, b to, c where the Trash put the source
}

// Record is one change in the journal Undo reads, newest first.
Record :: struct {
	id:     i64,
	change: Change,
	a, b, c: files.Path,
}

// --- effects ---------------------------------------------------------------

Effect :: union {
	// The filesystem's, in order; the first to fail stops the plan.
	Rename_Entry,
	Make_Folder,
	Trash_Entry,
	Restore_Entry,
	Start_Copy,
	Open_File,
	// The store's, in one transaction.
	Record_Visit,
	Add_Pin,
	Remove_Pin,
	Move_Places,
	Forget_Places,
	Journal,
	Unjournal,
	// The application's memory.
	Report,
	Withdraw,
	Ask,
	Settle,
	Stop_Copy,
}

// Rename_Entry renames from to to, failing rather than replacing an
// entry that is there by now.
Rename_Entry :: struct {
	from, to: files.Path,
}

Make_Folder :: struct {
	path: files.Path,
}

// Trash_Entry moves path to the Trash. A Journal later in the plan whose
// record leaves the Trash's path empty takes the path this one produced.
Trash_Entry :: struct {
	path: files.Path,
}

// Restore_Entry puts back what the Trash holds at trashed, at to.
Restore_Entry :: struct {
	trashed, to: files.Path,
}

// Start_Copy begins a copy of from to to in the background, an operation
// of its own in query.Activity; its end comes back as Copy_Done_Facts.
// then_trash makes it a move: the source goes to the Trash once the copy
// is whole.
Start_Copy :: struct {
	from, to:   files.Path,
	then_trash: bool,
}

Open_File :: struct {
	path: files.Path,
}

Record_Visit :: struct {
	path: files.Path,
	name: files.Name,
	dir:  bool,
}

Add_Pin :: struct {
	path: files.Path,
	name: files.Name,
}

Remove_Pin :: struct {
	path: files.Path,
}

// Move_Places makes the pins and recent places at or under from follow
// their entry to to.
Move_Places :: struct {
	from, to: files.Path,
}

// Forget_Places drops the pins and recent places at or under path.
Forget_Places :: struct {
	path: files.Path,
}

// Journal remembers a change for Undo.
Journal :: struct {
	record: Record,
}

// Unjournal forgets the change with id: undone, or past undoing.
Unjournal :: struct {
	id: i64,
}

// Report adds a problem to query.Activity.
Report :: struct {
	message: Message,
}

Withdraw :: struct {
	id: u64,
}

// Ask starts an operation that waits on a files.Resolve for paste.
Ask :: struct {
	question: Message,
	paste:    files.Paste,
}

// Settle ends operation op: answered, skipped or finished.
Settle :: struct {
	op: u64,
}

// Stop_Copy cancels the copy operation op is running.
Stop_Copy :: struct {
	op: u64,
}

// Plan is the effects a command comes to, in the order they are listed.
Plan :: struct {
	effects: [MAX_EFFECTS]Effect,
	count:   int,
}

add :: proc(p: ^Plan, e: Effect) {
	assert(p.count < MAX_EFFECTS, "files: a plan has more effects than MAX_EFFECTS")
	p.effects[p.count] = e
	p.count += 1
}

effects_of :: proc(p: ^Plan) -> []Effect {
	return p.effects[:p.count]
}

report :: proc(format: string, args: ..any) -> (p: Plan) {
	add(&p, Report{message(format, ..args)})
	return
}

// cut_short is the refusal for a command whose path did not fit its
// buffer, and true: the path it holds is a different, shorter one, so
// acting on it would act on the wrong entry.
@(private)
cut_short :: proc(paths: ..files.Path) -> (Plan, bool) {
	for &p in paths {
		if !files.path_fits(&p) {
			return report("That path is longer than %d bytes, too long to work with.", files.MAX_PATH), true
		}
	}
	return {}, false
}

// --- the simple flows --------------------------------------------------------

open :: proc(c: files.Open) -> (p: Plan) {
	if refusal, refused := cut_short(c.path); refused {
		return refusal
	}
	add(&p, Open_File{c.path})
	return
}

visited :: proc(c: files.Visited) -> (p: Plan) {
	add(&p, Record_Visit{c.path, c.name, c.dir})
	return
}

pin :: proc(c: files.Pin) -> (p: Plan) {
	add(&p, Add_Pin{c.path, c.name})
	return
}

unpin :: proc(c: files.Unpin) -> (p: Plan) {
	add(&p, Remove_Pin{c.path})
	return
}

dismiss :: proc(c: files.Dismiss) -> (p: Plan) {
	add(&p, Withdraw{c.id})
	return
}

// --- rename and new folder ---------------------------------------------------

Rename_Facts :: struct {
	exists:       bool,
	reason:       protection.Reason,
	siblings:     []string, // the names in its folder, its own among them
	places_under: bool, // pins or recent places at or under it
	on:           naming.Platform,
}

rename :: proc(c: files.Rename, f: Rename_Facts) -> Plan {
	c := c
	if refusal, refused := cut_short(c.path); refused {
		return refusal
	}
	from := files.path_of(&c.path)
	old := filepath.base(from)
	name := files.name_of(&c.name)
	if !f.exists {
		return report("“%s” is no longer there.", old)
	}
	if f.reason != .None {
		return report("“%s” can't be renamed: %s", old, why_protected(f.reason))
	}
	if v := naming.validity(name, f.on); v != .Valid {
		return report("“%s” can't be a name: %s", name, why_invalid(v))
	}
	if name == old {
		return {}
	}
	for s in f.siblings {
		if s != old && naming.same(s, name, f.on) {
			return report("There is already an item called “%s” here.", s)
		}
	}
	to := child(filepath.dir(from), name)
	p: Plan
	add(&p, Rename_Entry{c.path, to})
	if f.places_under {
		add(&p, Move_Places{c.path, to})
	}
	add(&p, Journal{{change = .Renamed, a = c.path, b = to}})
	return p
}

New_Folder_Facts :: struct {
	parent_is_dir: bool,
	siblings:      []string,
	on:            naming.Platform,
}

new_folder :: proc(c: files.New_Folder, f: New_Folder_Facts) -> Plan {
	c := c
	if refusal, refused := cut_short(c.parent); refused {
		return refusal
	}
	parent := files.path_of(&c.parent)
	wanted := files.name_of(&c.name)
	if v := naming.validity(wanted, f.on); v != .Valid {
		return report("“%s” can't be a name: %s", wanted, why_invalid(v))
	}
	if !f.parent_is_dir {
		return report("“%s” is no longer a folder.", filepath.base(parent))
	}
	buf: [files.MAX_NAME + 16]u8
	name := naming.free_name(wanted, f.siblings, f.on, true, buf[:])
	path := child(parent, name)
	p: Plan
	add(&p, Make_Folder{path})
	add(&p, Journal{{change = .Created, a = path}})
	return p
}

// --- trash ----------------------------------------------------------------------

Trash_Facts :: struct {
	exists:       bool,
	reason:       protection.Reason,
	places_under: bool,
}

trash :: proc(c: files.Trash, f: Trash_Facts) -> Plan {
	c := c
	if refusal, refused := cut_short(c.path); refused {
		return refusal
	}
	name := filepath.base(files.path_of(&c.path))
	if !f.exists {
		return report("“%s” is no longer there.", name)
	}
	if f.reason != .None {
		return report("“%s” can't go to the Trash: %s", name, why_protected(f.reason))
	}
	p: Plan
	add(&p, Trash_Entry{c.path})
	if f.places_under {
		add(&p, Forget_Places{c.path})
	}
	add(&p, Journal{{change = .Trashed, a = c.path}})
	return p
}

// --- paste ----------------------------------------------------------------------

Paste_Facts :: struct {
	source_exists: bool,
	source_is_dir: bool,
	dest_is_dir:   bool,
	same_volume:   bool,
	reason:        protection.Reason, // the source's
	siblings:      []string, // the names in dest
	places_under:  bool, // pins or recent places at or under the source
	on:            naming.Platform,
}

paste :: proc(c: files.Paste, f: Paste_Facts) -> Plan {
	c := c
	if refusal, refused := cut_short(c.source, c.dest); refused {
		return refusal
	}
	source := files.path_of(&c.source)
	dest := files.path_of(&c.dest)
	name := filepath.base(source)
	if refusal, refused := paste_refusal(c, f); refused {
		return refusal
	}
	m := placement.method({source = source, dest = dest, mode = c.mode, source_is_dir = f.source_is_dir, same_volume = f.same_volume, name_taken = naming.taken(name, f.siblings, f.on)})
	p: Plan
	switch m {
	case .Into_Itself:
		return report("“%s” can't go inside itself.", name)
	case .Already_There:
	case .Duplicate:
		buf: [files.MAX_NAME + 16]u8
		add(&p, Start_Copy{c.source, child(dest, naming.free_name(name, f.siblings, f.on, f.source_is_dir, buf[:])), false})
	case .Conflict:
		// The ui shows this after the operation's label, which names the
		// entry already: the question names only the folder.
		add(&p, Ask{message("“%s” already has an item called that.", filepath.base(dest)), c})
	case .Rename, .Copy, .Copy_Then_Trash:
		bring(&p, c, f, m, name)
	}
	return p
}

// paste_refusal is the plan for a paste that cannot happen at all, and
// true, or false when it may go ahead.
@(private)
paste_refusal :: proc(c: files.Paste, f: Paste_Facts) -> (refusal: Plan, refused: bool) {
	c := c
	name := filepath.base(files.path_of(&c.source))
	if !f.source_exists {
		return report("“%s” is no longer there.", name), true
	}
	if !f.dest_is_dir {
		return report("“%s” is no longer a folder.", filepath.base(files.path_of(&c.dest))), true
	}
	if c.mode == .Move && f.reason != .None {
		return report("“%s” can't be moved: %s", name, why_protected(f.reason)), true
	}
	return {}, false
}

// place adds the effects that bring the source into dest as name, by
// method m: a rename, or a copy that may end in the source's trash.
@(private)
bring :: proc(p: ^Plan, c: files.Paste, f: Paste_Facts, m: placement.Method, name: string) {
	c := c
	to := child(files.path_of(&c.dest), name)
	#partial switch m {
	case .Rename:
		add(p, Rename_Entry{c.source, to})
		if f.places_under {
			add(p, Move_Places{c.source, to})
		}
		add(p, Journal{{change = .Renamed, a = c.source, b = to}})
	case .Copy:
		add(p, Start_Copy{c.source, to, false})
	case .Copy_Then_Trash:
		add(p, Start_Copy{c.source, to, true})
	}
}

Resolve_Facts :: struct {
	asking: bool, // the operation still waits on an answer
	paste:  files.Paste, // what it asked about
	now:    Paste_Facts, // gathered again, for the answer
}

// resolve acts on the answer to a paste's question with the facts as
// they are now, not as they were when it asked.
resolve :: proc(c: files.Resolve, f: Resolve_Facts) -> Plan {
	if !f.asking {
		return {}
	}
	pc := f.paste
	source := files.path_of(&pc.source)
	dest := files.path_of(&pc.dest)
	name := filepath.base(source)
	p: Plan
	add(&p, Settle{c.op})
	if c.choice == .Skip {
		return p
	}
	if refusal, refused := paste_refusal(pc, f.now); refused {
		add(&p, refusal.effects[0])
		return p
	}
	method := placement.method({source = source, dest = dest, mode = pc.mode, source_is_dir = f.now.source_is_dir, same_volume = f.now.same_volume})
	if method == .Into_Itself || method == .Already_There {
		return p
	}
	if method == .Duplicate {
		method = .Copy
	}
	taken := naming.taken(name, f.now.siblings, f.now.on)
	switch c.choice {
	case .Keep_Both:
		buf: [files.MAX_NAME + 16]u8
		name = naming.free_name(name, f.now.siblings, f.now.on, f.now.source_is_dir, buf[:])
		bring(&p, pc, f.now, method, name)
	case .Replace:
		if taken {
			add(&p, Trash_Entry{child(dest, name)})
		}
		bring(&p, pc, f.now, method, name)
	case .Skip:
	}
	return p
}

// --- the end of a copy, and cancelling ------------------------------------------

Copy_Done_Facts :: struct {
	op:             u64,
	from, to:       files.Path,
	then_trash:     bool,
	ok:             bool,
	cancelled:      bool,
	error:          Message,
	partial_exists: bool, // something of the copy is at to
	places_under:   bool, // pins or recent places at or under from
}

copy_done :: proc(f: Copy_Done_Facts) -> (p: Plan) {
	f := f
	add(&p, Settle{f.op})
	name := filepath.base(files.path_of(&f.from))
	switch {
	case f.ok && f.then_trash:
		add(&p, Trash_Entry{f.from})
		if f.places_under {
			add(&p, Move_Places{f.from, f.to})
		}
		add(&p, Journal{{change = .Moved_Across, a = f.from, b = f.to}})
	case f.ok:
		add(&p, Journal{{change = .Copied, a = f.to}})
	case f.cancelled:
		if f.partial_exists {
			add(&p, Trash_Entry{f.to})
		}
	case:
		if f.partial_exists {
			add(&p, Trash_Entry{f.to})
		}
		add(&p, Report{message("“%s” couldn't be copied: %s", name, message_of(&f.error))})
	}
	return
}

Cancel_Facts :: struct {
	running: bool, // a copy
	asking:  bool, // a question
}

cancel :: proc(c: files.Cancel, f: Cancel_Facts) -> (p: Plan) {
	switch {
	case f.running:
		add(&p, Stop_Copy{c.op})
	case f.asking:
		add(&p, Settle{c.op})
	}
	return
}

// --- undo -------------------------------------------------------------------------

Undo_Facts :: struct {
	has:      bool, // the journal holds a change
	record:   Record,
	a_exists: bool,
	b_exists: bool,
	c_exists: bool,
	a_empty:  bool, // a is a folder with nothing in it
}

// undo reverses the newest change if the world still matches what it
// made; a change past undoing is reported and forgotten, so the next
// Undo reaches the one before it.
undo :: proc(f: Undo_Facts) -> Plan {
	if !f.has {
		return report("There is nothing to undo.")
	}
	e := f.record
	a := filepath.base(files.path_of(&e.a))
	p: Plan
	switch e.change {
	case .Renamed:
		if !f.b_exists || f.a_exists {
			return past_undoing(e.id, "“%s” has changed since it was renamed.", filepath.base(files.path_of(&e.b)))
		}
		add(&p, Rename_Entry{e.b, e.a})
		add(&p, Move_Places{e.b, e.a})
	case .Created:
		if !f.a_exists {
			break
		}
		if !f.a_empty {
			return past_undoing(e.id, "“%s” has things in it now.", a)
		}
		add(&p, Trash_Entry{e.a})
	case .Trashed:
		if e.b.len == 0 {
			return past_undoing(e.id, "Restore “%s” from the Recycle Bin.", a)
		}
		if !f.b_exists || f.a_exists {
			return past_undoing(e.id, "“%s” is no longer in the Trash, or its place is taken.", a)
		}
		add(&p, Restore_Entry{e.b, e.a})
	case .Copied:
		if f.a_exists {
			add(&p, Trash_Entry{e.a})
		}
	case .Moved_Across:
		if !f.b_exists || !f.c_exists || f.a_exists {
			return past_undoing(e.id, "“%s” has changed since it was moved.", a)
		}
		add(&p, Trash_Entry{e.b})
		add(&p, Restore_Entry{e.c, e.a})
		add(&p, Move_Places{e.b, e.a})
	}
	add(&p, Unjournal{e.id})
	return p
}

@(private)
past_undoing :: proc(id: i64, format: string, args: ..any) -> (p: Plan) {
	add(&p, Report{message(format, ..args)})
	add(&p, Unjournal{id})
	return
}

// undo_label is how query.Activity names what Undo would undo.
undo_label :: proc(e: ^Record) -> Message {
	a := filepath.base(files.path_of(&e.a))
	switch e.change {
	case .Renamed:
		return message("Undo rename of “%s”", a)
	case .Created:
		return message("Undo new folder “%s”", a)
	case .Trashed:
		return message("Undo move of “%s” to the Trash", a)
	case .Copied:
		return message("Undo copy “%s”", a)
	case .Moved_Across:
		return message("Undo move of “%s”", a)
	}
	return {}
}

// --- words ------------------------------------------------------------------------

@(private)
why_protected :: proc(r: protection.Reason) -> string {
	switch r {
	case .Root:
		return "it is the root of a drive."
	case .Home:
		return "it is your home folder."
	case .Place:
		return "your system keeps it there."
	case .None:
	}
	return ""
}

@(private)
why_invalid :: proc(v: naming.Validity) -> string {
	switch v {
	case .Empty:
		return "a name needs at least one character."
	case .Dots:
		return "“.” and “..” name folders already."
	case .Separator:
		return "a name can't hold a path separator."
	case .Bad_Character:
		return "it holds a character this system refuses."
	case .Reserved:
		return "this system keeps that name for a device."
	case .Trailing_Dot_Or_Space:
		return "this system drops a dot or space at the end."
	case .Too_Long:
		return "it is longer than 255 bytes."
	case .Valid:
	}
	return ""
}

// child is the path of name inside folder.
child :: proc(folder, name: string) -> (p: files.Path) {
	n := copy(p.buf[:], folder)
	if !strings.has_suffix(folder, filepath.SEPARATOR_STRING) && n < len(p.buf) {
		p.buf[n] = filepath.SEPARATOR
		n += 1
	}
	n += copy(p.buf[n:], name)
	p.len = n
	return
}
