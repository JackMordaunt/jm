package ui

import "base:runtime"
import "core:encoding/cbor"
import "core:mem"
import "core:strings"
import "core:sync"

// Needs and commands are the data half of a frame's traffic with its host,
// beside the input it takes and the scene it records. A frame is a function
// of plain data: the host gives it input and shapes, it gives back the
// scene, what it wants persisted (persist), what it asks of the platform
// (request.odin), the commands it has for the application, and the needs it
// has of the application's data. The ui never calls the application; the
// application never addresses the ui. Each is a value crossing a queue, so
// the two halves can sit in one process, two, or two machines, and a frame
// is tested by feeding it shapes and asserting on its needs and commands.
//
// A need is a query: a value of a type the application's contract declares,
// such as Users_Page{page = 3, size = 50}. need records it in this frame's
// set and returns whatever shape the host last delivered for it, keyed by
// the query's bytes, so two widgets asking the same question share one
// answer and a changed question is a new need. The set is rebuilt every
// frame; Subscriptions diffs it, so a host subscribes to what appeared and
// cancels what went, and a row scrolled out of view releases its avatar
// with no cleanup code in the widget.
//
// A command is a value the application processes: Create_User{...}. The ui
// learns nothing back from the call; an outcome comes back as data, under a
// need for it, so a form that wants to know carries a correlation id of its
// own in the command and needs Command_Outcome{id}.
//
// Both cross the boundary as bytes, kind and payload, so the ui package
// knows nothing of the contract's types: need and command marshal through
// core:encoding/cbor, and a host reads them back with need_as and
// command_as, or passes the bytes on untouched. kind is the query's type,
// "pkg.Name", which is how a host tells needs apart without decoding them.
//
//	page, status := ui.need(gtx, shapes.Users_Page{page = m.page, size = 50}, shapes.Users_Page_Result)
//	if status == .Missing || status == .Loading { skeleton(gtx); return }
//	for row in page.rows { ... }
//	if button(gtx, "Delete") { ui.command(gtx, shapes.Delete_User{id = row.id}) }
//
// A host, after the frame:
//
//	added, dropped := ui.subscriptions_update(&subs, ui.router_needs(&router))
//	for n in added { start(n) }       // a query to run, a pipeline to feed
//	for n in dropped { cancel(n) }
//	for c in ui.router_commands(&router) { app_send(c) }
//	ui.router_needs_clear(&router); ui.router_commands_clear(&router)
//
// and, when an answer lands, from any thread: ui.inbox_put_value(&inbox,
// query, result); the frame loop drains the inbox into the layout before
// the next frame, and the widget finds its shape Ready.

// Need_Key names a need: a hash of its kind and query bytes, the same in
// every process, so a shape delivered under it reaches the widget that
// asked whichever side of a pipe it is on.
Need_Key :: distinct u64

// Status is what a widget knows of a shape it needs. Missing is the first
// frame, before any host has seen the need; Loading once a host has; Ready
// when a shape is delivered; Stale when the host says a delivered shape is
// being refreshed, so the widget can keep showing it rather than a blank.
Status :: enum u8 {
	Missing,
	Loading,
	Ready,
	Stale,
}

// Need is one query a frame asked for, as the host sees it.
Need :: struct {
	key:   Need_Key,
	kind:  string, // the query's type, "pkg.Name"
	query: []byte, // the query value, cbor
}

// Command is one value a frame asked the application to process.
Command :: struct {
	kind: string, // the command's type, "pkg.Name"
	data: []byte, // the command value, cbor
}

// Delivery is a shape on its way to a layout: what a host puts in an Inbox
// and what the wire carries to a child.
Delivery :: struct {
	key:    Need_Key,
	status: Status,
	data:   []byte, // the shape, cbor; nil with Stale keeps what was delivered
}

// Shape_Entry is a delivered shape as the layout keeps it: its bytes, and
// the typed value decoded from them the first time a need reads it.
@(private)
Shape_Entry :: struct {
	data:            []byte, // in Layout.allocator
	status:          Status,
	version:         u64, // bumped by every delivery that carries bytes
	seen:            u64, // the last frame a need asked for it, or the delivery's
	decoded:         rawptr, // in arena; valid while decoded_version == version
	decoded_type:    typeid,
	decoded_version: u64,
	arena:           mem.Dynamic_Arena, // the decoded value and what it points to
	arena_live:      bool,
}

// need records that this frame wants the shape for query q and returns it
// as an R, typed, with its status. The pointer is nil unless the status is
// Ready or Stale. It is valid for the frame; a later delivery replaces the
// value behind it. q must be a named struct, enum or distinct type: its
// type name is the need's kind.
need :: proc(gtx: ^Ctx, q: $Q, $R: typeid) -> (r: ^R, status: Status) {
	r, status, _ = need_versioned(gtx, q, R)
	return
}

// need_versioned is need with the delivery's version: a count that moves
// with every delivery carrying new bytes, 0 while there is none. A widget
// that copies what it needs out of the shape, into a cache that outlives
// the need (a grid's pages), copies each delivery once by it.
need_versioned :: proc(gtx: ^Ctx, q: $Q, $R: typeid) -> (r: ^R, status: Status, version: u64) {
	kind := type_name(Q, gtx.allocator)
	bytes, ok := marshal_bytes(q, gtx.allocator)
	if !ok {
		return nil, .Missing, 0
	}
	key: Need_Key
	key, status = need_raw(gtx, kind, bytes)
	l := gtx.layout
	if l == nil || (status != .Ready && status != .Stale) {
		return nil, status, 0
	}
	e := &l.shapes[key]
	version = e.version
	if e.decoded != nil && e.decoded_type == R && e.decoded_version == e.version {
		return (^R)(e.decoded), status, version
	}
	if !e.arena_live {
		mem.dynamic_arena_init(&e.arena, l.allocator, l.allocator)
		e.arena_live = true
	} else {
		mem.dynamic_arena_free_all(&e.arena)
	}
	arena := mem.dynamic_arena_allocator(&e.arena)
	v := new(R, arena)
	if cbor.unmarshal_from_bytes(e.data, v, allocator = arena, temp_allocator = gtx.allocator) != nil {
		e.decoded = nil
		return nil, .Missing, 0
	}
	e.decoded, e.decoded_type, e.decoded_version = v, R, e.version
	return v, status, version
}

// need_raw is need with the query already marshalled: it records the need
// and returns its key, which deliver takes, and the shape's status.
need_raw :: proc(gtx: ^Ctx, kind: string, query: []byte) -> (key: Need_Key, status: Status) {
	key = need_key(kind, query)
	r := gtx.router
	if r != nil {
		known := false
		for n in r.needs {
			if n.key == key {
				known = true
				break
			}
		}
		if !known {
			append(&r.needs, Need{key, clone_string(kind, r.allocator), clone_bytes(query, r.allocator)})
		}
	}
	l := gtx.layout
	if l == nil {
		return key, .Missing
	}
	e, ok := &l.shapes[key]
	if !ok {
		return key, .Missing
	}
	e.seen = l.frame
	return key, e.status
}

// command asks the application to process c, once the frame is done. c is
// marshalled now; the ui learns nothing back.
command :: proc(gtx: ^Ctx, c: $C) {
	bytes, ok := marshal_bytes(c, gtx.allocator)
	if !ok {
		return
	}
	command_raw(gtx, type_name(C, gtx.allocator), bytes)
}

// command_raw is command with the value already marshalled.
command_raw :: proc(gtx: ^Ctx, kind: string, data: []byte) {
	r := gtx.router
	if r == nil {
		return
	}
	append(&r.commands, Command{clone_string(kind, r.allocator), clone_bytes(data, r.allocator)})
}

// need_key is the key need gives a query of kind with these bytes.
need_key :: proc(kind: string, query: []byte) -> Need_Key {
	h := fnv_bytes(FNV_OFFSET, transmute([]u8)kind)
	h = fnv_bytes(h, {0})
	return Need_Key(fnv_bytes(h, query))
}

// key_of is the key need would give q: what a host delivers a shape under
// when it computes the answer from its own copy of the query.
key_of :: proc(q: $Q, allocator := context.temp_allocator) -> Need_Key {
	bytes, ok := marshal_bytes(q, allocator)
	if !ok {
		return 0
	}
	return need_key(type_name(Q, allocator), bytes)
}

// need_is reports whether n's query is a Q.
need_is :: proc(n: Need, $Q: typeid) -> bool {
	return n.kind == type_name(Q, context.temp_allocator)
}

// need_as decodes n's query as a Q, into allocator. False when n is not a Q
// or does not decode.
need_as :: proc(n: Need, $Q: typeid, allocator := context.temp_allocator) -> (q: Q, ok: bool) {
	if !need_is(n, Q) {
		return {}, false
	}
	if cbor.unmarshal_from_bytes(n.query, &q, allocator = allocator, temp_allocator = allocator) != nil {
		return {}, false
	}
	return q, true
}

// command_is reports whether c is a C.
command_is :: proc(c: Command, $C: typeid) -> bool {
	return c.kind == type_name(C, context.temp_allocator)
}

// command_as decodes c as a C, into allocator. False when c is not a C or
// does not decode.
command_as :: proc(c: Command, $C: typeid, allocator := context.temp_allocator) -> (v: C, ok: bool) {
	if !command_is(c, C) {
		return {}, false
	}
	if cbor.unmarshal_from_bytes(c.data, &v, allocator = allocator, temp_allocator = allocator) != nil {
		return {}, false
	}
	return v, true
}

// needs_count and needs_rewind bracket a layout pass whose needs do not
// count, such as ui.list measuring a row it does not show: the needs
// recorded since the mark are forgotten.
@(private)
needs_count :: proc(gtx: ^Ctx) -> int {
	return len(gtx.router.needs) if gtx.router != nil else 0
}

@(private)
needs_rewind :: proc(gtx: ^Ctx, mark: int) {
	r := gtx.router
	if r == nil {
		return
	}
	for n in r.needs[mark:] {
		delete(n.kind, r.allocator)
		delete(n.query, r.allocator)
	}
	resize(&r.needs, mark)
}

// router_needs is the set of needs the frames since the last
// router_needs_clear asked for, each once, in the order first asked. A host
// clears it every frame, since a need is a frame's claim, not a standing one.
router_needs :: proc(r: ^Router) -> []Need {
	return r.needs[:]
}

// router_needs_clear forgets the needs router_needs returned.
router_needs_clear :: proc(r: ^Router) {
	for n in r.needs {
		delete(n.kind, r.allocator)
		delete(n.query, r.allocator)
	}
	clear(&r.needs)
}

// router_commands is what the frames since the last router_commands_clear
// asked the application to process, in the order asked.
router_commands :: proc(r: ^Router) -> []Command {
	return r.commands[:]
}

// router_commands_clear forgets the commands router_commands returned, once
// they have been passed on.
router_commands_clear :: proc(r: ^Router) {
	for c in r.commands {
		delete(c.kind, r.allocator)
		delete(c.data, r.allocator)
	}
	clear(&r.commands)
}

// deliver gives the layout a shape under key, copying data: the next frame's
// need for it finds status. A Stale delivery with nil data keeps the bytes
// delivered before and only changes the status; any other delivery with nil
// data clears them. Call it on the thread that runs frames; from another,
// put it in an Inbox.
deliver :: proc(l: ^Layout, key: Need_Key, data: []byte, status: Status = .Ready) {
	e, ok := &l.shapes[key]
	if !ok {
		l.shapes[key] = {}
		e = &l.shapes[key]
	}
	if !(status == .Stale && data == nil) {
		delete(e.data, l.allocator)
		e.data = clone_bytes(data, l.allocator)
		e.version += 1
	}
	e.status = status
	e.seen = l.frame
}

// shapes_reset drops every shape no need asked for since the frame before,
// as layout_reset drops a widget's state, and marks the rest.
@(private)
shapes_reset :: proc(l: ^Layout) {
	stale := make([dynamic]Need_Key, context.temp_allocator)
	for k, e in l.shapes {
		if e.seen + 1 < l.frame {
			append(&stale, k)
		}
	}
	for k in stale {
		shape_entry_free(l, &l.shapes[k])
		delete_key(&l.shapes, k)
	}
}

@(private)
shape_entry_free :: proc(l: ^Layout, e: ^Shape_Entry) {
	delete(e.data, l.allocator)
	if e.arena_live {
		mem.dynamic_arena_destroy(&e.arena)
	}
	e^ = {}
}

// ---------------------------------------------------------------------------
// Subscriptions: a host's view of the need set, frame to frame
// ---------------------------------------------------------------------------

// Subscriptions is the diff a host keeps between one frame's needs and the
// next: what to start and what to cancel. The needs it holds are its own
// copies.
Subscriptions :: struct {
	allocator: mem.Allocator,
	live:      map[Need_Key]Need,
	seen:      map[Need_Key]u64,
	frame:     u64,
	added:     [dynamic]Need, // this update's new needs; entries of live
	dropped:   [dynamic]Need, // this update's gone needs; freed by the next update
}

subscriptions_init :: proc(s: ^Subscriptions, allocator := context.allocator) {
	s.allocator = allocator
	s.live = make(map[Need_Key]Need, allocator)
	s.seen = make(map[Need_Key]u64, allocator)
	s.added = make([dynamic]Need, allocator)
	s.dropped = make([dynamic]Need, allocator)
}

subscriptions_destroy :: proc(s: ^Subscriptions) {
	for _, n in s.live {
		need_free(n, s.allocator)
	}
	for n in s.dropped {
		need_free(n, s.allocator)
	}
	delete(s.live)
	delete(s.seen)
	delete(s.added)
	delete(s.dropped)
	s^ = {}
}

// subscriptions_update takes a frame's need set and returns what is new
// since the last update and what is gone. Both slices are valid until the
// next update; a host starts the added and cancels the dropped.
subscriptions_update :: proc(s: ^Subscriptions, needs: []Need) -> (added, dropped: []Need) {
	for n in s.dropped {
		need_free(n, s.allocator)
	}
	clear(&s.dropped)
	clear(&s.added)
	s.frame += 1
	for n in needs {
		if _, ok := s.live[n.key]; !ok {
			kept := Need{n.key, clone_string(n.kind, s.allocator), clone_bytes(n.query, s.allocator)}
			s.live[n.key] = kept
			append(&s.added, kept)
		}
		s.seen[n.key] = s.frame
	}
	gone := make([dynamic]Need_Key, context.temp_allocator)
	for k, f in s.seen {
		if f != s.frame {
			append(&gone, k)
		}
	}
	for k in gone {
		append(&s.dropped, s.live[k])
		delete_key(&s.live, k)
		delete_key(&s.seen, k)
	}
	return s.added[:], s.dropped[:]
}

// subscriptions_live reports whether key is still needed: what a host
// checks before it delivers an answer that took a while, so a result for
// a need that went meanwhile is dropped at the door.
subscriptions_live :: proc(s: ^Subscriptions, key: Need_Key) -> bool {
	_, ok := s.live[key]
	return ok
}

@(private)
need_free :: proc(n: Need, allocator: mem.Allocator) {
	delete(n.kind, allocator)
	delete(n.query, allocator)
}

// ---------------------------------------------------------------------------
// Inbox: shapes arriving from any thread
// ---------------------------------------------------------------------------

// Inbox is where shapes wait between the thread that made them and the
// frame loop: inbox_put from any thread, inbox_drain on the frame's. The
// loop that owns a layout drains it before every frame; a host over the
// wire takes it and sends it. A later put under a key replaces an earlier
// one still waiting, so a burst of answers costs the frame one delivery.
Inbox :: struct {
	mutex:     sync.Mutex,
	allocator: mem.Allocator,
	items:     [dynamic]Delivery, // own copies
}

inbox_init :: proc(ib: ^Inbox, allocator := context.allocator) {
	ib.allocator = allocator
	ib.items = make([dynamic]Delivery, allocator)
}

inbox_destroy :: proc(ib: ^Inbox) {
	for d in ib.items {
		delete(d.data, ib.allocator)
	}
	delete(ib.items)
	ib^ = {}
}

// inbox_put queues a shape for key, copying data. Any thread may call it.
inbox_put :: proc(ib: ^Inbox, key: Need_Key, data: []byte, status: Status = .Ready) {
	sync.mutex_guard(&ib.mutex)
	for &d in ib.items {
		if d.key == key {
			if !(status == .Stale && data == nil) {
				delete(d.data, ib.allocator)
				d.data = clone_bytes(data, ib.allocator)
			}
			d.status = status
			return
		}
	}
	append(&ib.items, Delivery{key, status, clone_bytes(data, ib.allocator)})
}

// inbox_put_value is inbox_put with the shape as a value for query q.
inbox_put_value :: proc(ib: ^Inbox, q: $Q, v: $R, status: Status = .Ready) {
	bytes, ok := marshal_bytes(v, context.temp_allocator)
	if !ok {
		return
	}
	inbox_put(ib, key_of(q), bytes, status)
}

// inbox_drain delivers everything waiting into l and empties the inbox,
// reporting whether anything was. The frame loop's thread calls it.
inbox_drain :: proc(ib: ^Inbox, l: ^Layout) -> bool {
	sync.mutex_guard(&ib.mutex)
	for d in ib.items {
		deliver(l, d.key, d.data, d.status)
		delete(d.data, ib.allocator)
	}
	had := len(ib.items) > 0
	clear(&ib.items)
	return had
}

// inbox_take moves everything waiting out of the inbox into a slice from
// allocator, for a host that sends it on rather than delivering it here.
// The data in it is copied; the inbox is empty afterwards.
inbox_take :: proc(ib: ^Inbox, allocator := context.temp_allocator) -> []Delivery {
	sync.mutex_guard(&ib.mutex)
	out := make([]Delivery, len(ib.items), allocator)
	for d, ii in ib.items {
		out[ii] = Delivery{d.key, d.status, clone_bytes(d.data, allocator)}
		delete(d.data, ib.allocator)
	}
	clear(&ib.items)
	return out
}

// inbox_pending reports whether anything waits, without taking it: a frame
// loop asks before deciding whether a frame is due.
inbox_pending :: proc(ib: ^Inbox) -> bool {
	sync.mutex_guard(&ib.mutex)
	return len(ib.items) > 0
}

// ---------------------------------------------------------------------------
// Data_Host: the application's side of a frame loop
// ---------------------------------------------------------------------------

// Data_Host is how a frame loop hands the application what a frame needs
// and asks, and where the application's answers come back: shell.App,
// shell.Host_App and child.App carry one. on_need is called once when a need
// appears and once when it goes; on_command for each command, in order;
// both on the loop's thread, after the frame. An answer is put in inbox
// from any thread (inbox_put_value) and reaches the next frame; a loop
// with no inbox delivers nothing. Nil callbacks drop what they would get.
Data_Host :: struct {
	user:       rawptr,
	on_need:    proc(user: rawptr, need: Need, added: bool),
	on_command: proc(user: rawptr, c: Command),
	inbox:      ^Inbox,
}

// data_dispatch hands a frame's need diff and commands to h's callbacks.
data_dispatch :: proc(h: ^Data_Host, added, dropped: []Need, commands: []Command) {
	if h.on_need != nil {
		for n in added {
			h.on_need(h.user, n, true)
		}
		for n in dropped {
			h.on_need(h.user, n, false)
		}
	}
	if h.on_command != nil {
		for c in commands {
			h.on_command(h.user, c)
		}
	}
}

// data_after_frame is what a loop does with the router once a frame is
// done: diff its needs against the last frame's through subs, dispatch
// the diff and the commands to h, and clear the router for the next frame.
data_after_frame :: proc(h: ^Data_Host, subs: ^Subscriptions, r: ^Router) {
	added, dropped := subscriptions_update(subs, router_needs(r))
	data_dispatch(h, added, dropped, router_commands(r))
	router_needs_clear(r)
	router_commands_clear(r)
}

// ---------------------------------------------------------------------------

// type_name is "pkg.Name" for a named type, what need and command send as
// kind; it asserts on an unnamed one, since a contract declares its
// queries and commands as named types.
@(private)
type_name :: proc(id: typeid, allocator: mem.Allocator) -> string {
	info := type_info_of(id)
	named, ok := info.variant.(runtime.Type_Info_Named)
	assert(ok, "ui: a need or command must be a named type")
	return strings.concatenate({named.pkg, ".", named.name}, allocator)
}

// marshal_bytes is v as cbor, in allocator; false when v has no encoding.
@(private)
marshal_bytes :: proc(v: any, allocator: mem.Allocator) -> ([]byte, bool) {
	out, err := cbor.marshal_into_bytes(v, allocator = allocator, temp_allocator = allocator)
	return out, err == nil
}

@(private)
clone_bytes :: proc(b: []byte, allocator: mem.Allocator) -> []byte {
	if b == nil {
		return nil
	}
	out := make([]byte, len(b), allocator)
	copy(out, b)
	return out
}
