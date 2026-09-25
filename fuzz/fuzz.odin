/*
Package fuzz runs properties against generated input and tells you the
smallest case that broke one.

	suite := fuzz.Suite(tar.Reader) {
		name       = "tar",
		setup      = open_reader,
		teardown   = close_reader,
		properties = []fuzz.Property(tar.Reader){{"never_panics", never_panics}},
	}
	report := fuzz.run(suite, {seed = 1, iterations = 10_000})

A property is handed the subject and a Source, draws whatever input it wants
from that Source, and says whether the promise held. Everything else is this
package's job: seeding, budgets, a fresh arena per case, shrinking a failure
to its simplest form, saving it as a regression, and stopping a case that
will not finish.

A case is a pure function of the bytes it drew, which is what makes the rest
work. Set `corpus_dir` and a failure is written there and replayed first on
every later run, so a bug found once is a test from then on.

Each suite names how to make a subject, how to throw it away, and, if it has
one, how to cancel work in flight. Without `cancel` there is no deadline: a
property that hangs hangs the run, because nothing else can stop it.
*/
package fuzz

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// Property is one promise, and how to check it against a subject. Draw the
// input from src; return the detail of what went wrong and whether it held.
Property :: struct($S: typeid) {
	name:  string,
	check: proc(subject: S, src: ^Source) -> (detail: string, ok: bool),
}

// Suite is a subject and the promises it makes.
Suite :: struct($S: typeid) {
	name:       string,
	// Make a subject for one case. Called again for every shrink attempt, so
	// no case can inherit state from the one before it.
	setup:      proc() -> (S, bool),
	// Throw the subject away. nil if there is nothing to release.
	teardown:   proc(subject: ^S),
	// Stop whatever the subject is doing, from another thread, so a case
	// that overruns can be cut short. nil means no deadline is enforced.
	cancel:     proc(subject: S),
	properties: []Property(S),
}

// Opts bounds a run. The zero value is a thousand cases from a seed off the
// clock, shrinking every failure, saving none.
Opts :: struct {
	// The seed to replay. 0 takes one from the clock and reports it.
	seed:          u64,
	// How many cases to run. 0 means a thousand.
	iterations:    int,
	// Stop after this long, whatever is left. 0 is no limit.
	duration:      time.Duration,
	// Stop at the first failure rather than collecting them all.
	stop_on_first: bool,
	// Bytes of randomness a case may draw before it wraps. 0 means 256.
	entropy:       int,
	// How long one case may run before cancel is called on it and it is
	// reported as a hang. 0 means five seconds. Ignored without Suite.cancel.
	case_timeout:  time.Duration,
	// How many smaller cases to try when shrinking a failure. 0 means 300.
	// Negative turns shrinking off.
	shrink:        int,
	// Where to read regressions from and write new ones to. "" is neither.
	//
	// Setting it also leaves a breadcrumb: the case about to run is written
	// out first and removed once it comes back. A property that takes the
	// process down with it — a panic, a failed bounds check, anything the
	// harness cannot catch — therefore leaves the case that did it on disk,
	// and the next run replays it. That costs a file write per case, which
	// is why it only happens when a corpus is asked for.
	corpus_dir:    string,
	// Run each case in a child process. It costs a spawn per case, which is
	// an order of magnitude slower; the README records the measurement and
	// the command that makes it. In return nothing a property does can end
	// the run — a panic, a bounds check or a loop with no end come back as a
	// result like any other — and the deadline works whether or not the
	// suite supplies cancel.
	isolate:       bool,
	// What to spawn for a child. Empty means this binary, re-run with the
	// case named in its environment, which is what a suite wants. A test
	// points it somewhere else to drive the machinery on its own.
	child_command: []string,
	// Called on each failure, and every thousand cases. nil is silent.
	log:           proc(format: string, args: ..any),
}

// Failure is one property that did not hold, and the case that broke it.
Failure :: struct {
	property:  string,
	iteration: int,
	// The seed the run used. Replaying it reaches this case again.
	seed:      u64,
	detail:    string,
	// The bytes the case drew from, after shrinking. Feed them back to
	// replay it on their own.
	entropy:   []byte,
	// How much smaller shrinking made it, in bytes. 0 means it did not help.
	shrunk_by: int,
	// Where the case was saved, if corpus_dir was set.
	saved:     string,
	// How the case ended. In this process only Held, Failed and Hung can be
	// told apart; a child can also come back Crashed or Broken.
	outcome:   Outcome,
	// Set when the case had to be cancelled rather than finishing.
	hung:      bool,
}

// Report is what a run found. Everything in it is allocated in the allocator
// run was given, and belongs to the caller.
Report :: struct {
	seed:       u64,
	iterations: int,
	elapsed:    time.Duration,
	failures:   []Failure,
	// How many regressions from corpus_dir were replayed before the
	// generated cases started.
	replayed:   int,
	// A fingerprint of every case the run generated. Two runs of one seed
	// agree on it; a run that generated anything differently does not. It is
	// what makes determinism checkable when nothing failed.
	digest:     u64,
}

// Watchdog cancels a case that overruns. The mutex covers every field, so the
// subject cannot be torn down between the deadline check and the cancel.
//
// It holds the subject as a rawptr and reaches the suite's typed cancel
// through invoke, which arm builds for the subject's type. That keeps the
// thread, and everything that touches it, free of the type parameter.
@(private)
Watchdog :: struct {
	mutex:    sync.Mutex,
	subject:  rawptr,
	cancel:   rawptr,
	invoke:   proc(cancel: rawptr, subject: rawptr),
	live:     bool,
	deadline: time.Time,
	fired:    bool,
	stop:     bool,
}

// arm points the watchdog at one case's subject, and teaches it how to call
// the suite's cancel on a value of that type.
@(private)
arm :: proc(dog: ^Watchdog, subject: ^$S, cancel: proc(_: S), deadline: time.Time) {
	sync.lock(&dog.mutex)
	dog.subject = subject
	dog.cancel = rawptr(cancel)
	dog.invoke = proc(c: rawptr, s: rawptr) {
		f := cast(proc(_: S))c
		f((^S)(s)^)
	}
	dog.live = true
	dog.fired = false
	dog.deadline = deadline
	sync.unlock(&dog.mutex)
}

// disarm retires the subject before it is torn down, so a cancel can never
// land on something already released, and reports whether one was fired.
@(private)
disarm :: proc(dog: ^Watchdog) -> (fired: bool) {
	sync.lock(&dog.mutex)
	fired = dog.fired
	dog.live = false
	dog.subject = nil
	sync.unlock(&dog.mutex)
	return fired
}

// start_watchdog runs the deadline thread.
@(private)
start_watchdog :: proc(dog: ^Watchdog) -> ^thread.Thread {
	return thread.create_and_start_with_poly_data(dog, watch)
}

// stop_watchdog ends the deadline thread and waits for it.
@(private)
stop_watchdog :: proc(dog: ^Watchdog, guard: ^thread.Thread) {
	if guard == nil {
		return
	}
	sync.lock(&dog.mutex)
	dog.stop = true
	sync.unlock(&dog.mutex)
	thread.join(guard)
	thread.destroy(guard)
}

// seed_generator makes the run's randomness a function of its seed.
@(private)
seed_generator :: proc(seed: u64, state: ^rand.Default_Random_State) -> runtime.Random_Generator {
	state^ = rand.create(seed)
	return runtime.default_random_generator(state)
}

// fill_entropy draws one case's worth of randomness.
@(private)
fill_entropy :: proc(dst: []byte) {
	for i in 0 ..< len(dst) {
		dst[i] = byte(rand.uint32())
	}
}

DEFAULT_ITERATIONS   :: 1000
DEFAULT_ENTROPY      :: 256
DEFAULT_SHRINK       :: 300
DEFAULT_CASE_TIMEOUT :: 5 * time.Second

// run checks the suite's properties against generated cases and reports what
// failed, smallest form first.
run :: proc(suite: Suite($S), opts := Opts{}, allocator := context.allocator) -> Report {
	// A child is this same binary with one case named in its environment.
	// Serving it here means a program that calls run is its own child with
	// no further wiring, and it must happen before anything else: a child
	// that set up a run of its own would fork for ever.
	if spec, is_child := os.lookup_env(ENV_CASE, context.temp_allocator); is_child {
		if !serve_one(suite, spec) {
			// Another suite in this binary owns the case.
			return {}
		}
	}

	opts := opts
	if opts.seed == 0 {
		opts.seed = u64(time.now()._nsec) | 1
	}
	if opts.iterations == 0 {
		opts.iterations = DEFAULT_ITERATIONS
	}
	if opts.entropy <= 0 {
		opts.entropy = DEFAULT_ENTROPY
	}
	if opts.shrink == 0 {
		opts.shrink = DEFAULT_SHRINK
	}
	timeout := opts.case_timeout if opts.case_timeout > 0 else DEFAULT_CASE_TIMEOUT

	state: rand.Default_Random_State
	context.random_generator = seed_generator(opts.seed, &state)

	iso: ^Isolation
	if opts.isolate {
		started, ierr := start_isolation(opts.child_command, context.temp_allocator)
		if ierr != "" {
			// Without children there is no run to make, and pretending
			// otherwise would report a clean sweep of nothing.
			failures := make([dynamic]Failure, allocator)
			append(
				&failures,
				Failure {
					property = suite.name,
					seed = opts.seed,
					detail = strings.clone(ierr, allocator),
					outcome = .Broken,
				},
			)
			return Report{seed = opts.seed, failures = failures[:]}
		}
		iso = started
	}
	defer stop_isolation(iso)

	dog := new(Watchdog, context.temp_allocator)
	guard: ^thread.Thread
	// A child is held to its deadline by being killed, so the watchdog is
	// only wanted when cases run here.
	if suite.cancel != nil && iso == nil {
		guard = start_watchdog(dog)
	}
	defer stop_watchdog(dog, guard)

	failures := make([dynamic]Failure, allocator)
	started := time.now()
	digest := u64(1469598103934665603)
	done := 0

	// Regressions first: a case that failed once is checked on every run
	// from then on, before anything new is tried.
	saved := load_corpus(opts.corpus_dir, context.temp_allocator)
	for entry in saved {
		i, found := property_index(suite, entry.property)
		if !found {
			continue
		}
		// A case left behind by a run that died is promoted to a permanent
		// regression before it is replayed, so it survives both outcomes:
		// dying again, and passing once the bug is fixed.
		_ = save_case(opts.corpus_dir, entry.property, entry.entropy, context.temp_allocator)
		crumb := ""
		if iso == nil {
			crumb = drop_crumb(opts.corpus_dir, entry.property, entry.entropy)
		}
		detail, ok, outcome := attempt(suite, i, entry.entropy, dog, timeout, suite.cancel, iso)
		clear_crumb(crumb)
		done += 1
		if !ok {
			record(
				&failures,
				suite.properties[i].name,
				done - 1,
				opts,
				detail,
				entry.entropy,
				0,
				entry.path,
				outcome,
				allocator,
			)
			if opts.stop_on_first {
				break
			}
		}
	}
	replayed := done

	if !(opts.stop_on_first && len(failures) > 0) {
		for i in 0 ..< opts.iterations {
			if opts.duration > 0 && time.since(started) >= opts.duration {
				break
			}
			which := i % len(suite.properties)
			entropy := make([]byte, opts.entropy, context.temp_allocator)
			fill_entropy(entropy)
			digest = (digest ~ u64(which) ~ fnv(entropy)) * 1099511628211
			done += 1

			// A child that dies is reported by its parent, so the
			// breadcrumb is only needed when the case runs here.
			// A child that dies is reported by its parent, so the
			// breadcrumb is only needed when the case runs here.
			crumb := ""
			if iso == nil {
				crumb = drop_crumb(opts.corpus_dir, suite.properties[which].name, entropy)
			}
			detail, ok, outcome := attempt(suite, which, entropy, dog, timeout, suite.cancel, iso)
			clear_crumb(crumb)
			if !ok {
				small, steps, small_detail := shrink(
					suite,
					which,
					entropy,
					dog,
					timeout,
					suite.cancel,
					iso,
					opts.shrink,
				)
				if small_detail != "" {
					detail = small_detail
				}
				path := save_case(
					opts.corpus_dir,
					suite.properties[which].name,
					small,
					context.temp_allocator,
				)
				record(
					&failures,
					suite.properties[which].name,
					i,
					opts,
					detail,
					small,
					steps,
					path,
					outcome,
					allocator,
				)
				if opts.stop_on_first {
					break
				}
			}
			if opts.log != nil && done % 1000 == 0 {
				opts.log("%d cases, %d failures", done, len(failures))
			}
		}
	}

	return Report {
		seed = opts.seed,
		iterations = done,
		elapsed = time.since(started),
		failures = failures[:],
		replayed = replayed,
		digest = digest,
	}
}

// attempt runs one case: a fresh subject, a fresh arena, and the property
// over the given entropy.
@(private)
attempt :: proc(
	suite: Suite($S),
	which: int,
	entropy: []byte,
	dog: ^Watchdog,
	timeout: time.Duration,
	cancel: proc(subject: S),
	iso: ^Isolation,
) -> (
	detail: string,
	ok: bool,
	outcome: Outcome,
) {
	if iso != nil {
		d, o := run_isolated(
			iso,
			suite.name,
			suite.properties[which].name,
			entropy,
			timeout,
			context.temp_allocator,
		)
		return d, o == .Held, o
	}
	// The case owns an arena, so nothing it allocated can outlive it and no
	// case can be handed memory the one before it left behind. The detail is
	// the one thing that has to survive, so it is copied out into the
	// caller's allocator before the arena goes.
	caller := context
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)

	context.allocator = mem.dynamic_arena_allocator(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)

	subject: S
	if suite.setup != nil {
		made: bool
		subject, made = suite.setup()
		if !made {
			return "setup failed", false, .Broken
		}
	}

	if cancel != nil {
		arm(dog, &subject, cancel, time.time_add(time.now(), timeout))
	}

	src := source(entropy)
	detail, ok = suite.properties[which].check(subject, &src)

	hung := false
	if cancel != nil {
		hung = disarm(dog)
	}
	if suite.teardown != nil {
		suite.teardown(&subject)
	}

	if hung {
		if detail == "" {
			return fmt.aprintf(
					"did not finish within %v",
					timeout,
					allocator = caller.temp_allocator,
				),
				false,
				.Hung
		}
		return fmt.aprintf(
				"did not finish within %v, then: %s",
				timeout,
				detail,
				allocator = caller.temp_allocator,
			),
			false,
			.Hung
	}
	return strings.clone(detail, caller.temp_allocator), ok, ok ? .Held : .Failed
}

// watch cancels a case that has run past its deadline, and keeps cancelling
// until the case retires its subject. Cancelling once is not enough: a
// property runs several operations, and the next would hang in place of the
// one that was stopped.
@(private)
watch :: proc(dog: ^Watchdog) {
	for {
		time.sleep(10 * time.Millisecond)
		sync.lock(&dog.mutex)
		if dog.stop {
			sync.unlock(&dog.mutex)
			return
		}
		if dog.live && time.since(dog.deadline) > 0 {
			dog.invoke(dog.cancel, dog.subject)
			dog.fired = true
		}
		sync.unlock(&dog.mutex)
	}
}

// shrink looks for a smaller entropy string that fails the same property. It
// tries the obvious simplifications in order of how much they remove: cut the
// tail, drop a byte, zero a byte, halve a byte. Each success restarts the
// search from the smaller case.
@(private)
shrink :: proc(
	suite: Suite($S),
	which: int,
	entropy: []byte,
	dog: ^Watchdog,
	timeout: time.Duration,
	cancel: proc(subject: S),
	iso: ^Isolation,
	budget: int,
) -> (
	smallest: []byte,
	steps: int,
	detail: string,
) {
	smallest = entropy
	if budget < 0 {
		return smallest, 0, ""
	}
	spent := 0
	improved := true
	for improved && spent < budget {
		improved = false

		// Cut the tail back first. A case that drew less than it was given
		// loses nothing by it, and it is the step that removes the most.
		for cut := len(smallest) / 2; cut > 0 && spent < budget; cut /= 2 {
			candidate := smallest[:len(smallest) - cut]
			spent += 1
			if d, ok, _ := attempt(suite, which, candidate, dog, timeout, cancel, iso); !ok {
				smallest, detail, improved = candidate, d, true
				break
			}
		}
		if improved {
			continue
		}

		// Then one byte at a time: remove it, zero it, or halve it.
		for i := 0; i < len(smallest) && spent < budget; i += 1 {
			if smallest[i] == 0 {
				continue
			}
			for attemptv in 0 ..< 3 {
				if spent >= budget {
					break
				}
				candidate := make([dynamic]byte, 0, len(smallest), context.temp_allocator)
				switch attemptv {
				case 0:
					append(&candidate, ..smallest[:i])
					append(&candidate, ..smallest[i + 1:])
				case 1:
					append(&candidate, ..smallest)
					candidate[i] = 0
				case 2:
					append(&candidate, ..smallest)
					candidate[i] = smallest[i] / 2
				}
				spent += 1
				if d, ok, _ := attempt(suite, which, candidate[:], dog, timeout, cancel, iso);
				   !ok {
					smallest, detail, improved = candidate[:], d, true
					break
				}
			}
			if improved {
				break
			}
		}
	}
	return smallest, len(entropy) - len(smallest), detail
}

// record adds a failure, cloned into the caller's allocator.
@(private)
record :: proc(
	failures: ^[dynamic]Failure,
	property: string,
	iteration: int,
	opts: Opts,
	detail: string,
	entropy: []byte,
	shrunk_by: int,
	saved: string,
	outcome: Outcome,
	allocator: mem.Allocator,
) {
	kept := make([]byte, len(entropy), allocator)
	copy(kept, entropy)
	f := Failure {
		property  = property,
		iteration = iteration,
		seed      = opts.seed,
		detail    = strings.clone(detail, allocator),
		entropy   = kept,
		shrunk_by = shrunk_by,
		saved     = strings.clone(saved, allocator),
		outcome   = outcome,
		hung      = outcome == .Hung,
	}
	append(failures, f)
	if opts.log != nil {
		opts.log("%s failed at case %d: %s", property, iteration, f.detail)
	}
}

// property_index finds a property by name, for replaying a saved case
// against the property it was saved from.
@(private)
property_index :: proc(suite: Suite($S), name: string) -> (int, bool) {
	for p, i in suite.properties {
		if p.name == name {
			return i, true
		}
	}
	return 0, false
}

// Regression is one case read back from the corpus directory.
@(private)
Regression :: struct {
	property: string,
	entropy:  []byte,
	path:     string,
}

// load_corpus reads every case in dir. A case's file name carries the
// property it belongs to, so it is replayed against the right one.
@(private)
load_corpus :: proc(dir: string, allocator := context.allocator) -> []Regression {
	out := make([dynamic]Regression, allocator)
	if dir == "" || !os.is_dir(dir) {
		return out[:]
	}
	f, err := os.open(dir)
	if err != nil {
		return out[:]
	}
	defer os.close(f)
	entries, rerr := os.read_directory(f, -1, allocator)
	if rerr != nil {
		return out[:]
	}
	for e in entries {
		if !strings.has_suffix(e.name, CASE_SUFFIX) {
			continue
		}
		stem := e.name[:len(e.name) - len(CASE_SUFFIX)]
		dash := strings.last_index_byte(stem, '-')
		if dash <= 0 {
			continue
		}
		path, _ := filepath.join({dir, e.name}, allocator)
		data, derr := os.read_entire_file_from_path(path, allocator)
		if derr != nil {
			continue
		}
		append(&out, Regression{property = stem[:dash], entropy = data, path = path})
	}
	return out[:]
}

CASE_SUFFIX :: ".case"

// CRUMB_MARK names the case a run is in the middle of. It is left behind only
// when the run did not survive it, and it is read back as a regression
// because the name before the last dash is still the property's.
CRUMB_MARK :: "-crashed"

// drop_crumb records the case about to run, so a property that kills the
// process leaves behind the input that did it.
@(private)
drop_crumb :: proc(dir, property: string, entropy: []byte) -> string {
	if dir == "" {
		return ""
	}
	if err := os.make_directory_all(dir); err != nil && !os.is_dir(dir) {
		return ""
	}
	path, _ := filepath.join(
		{dir, fmt.tprintf("%s%s%s", property, CRUMB_MARK, CASE_SUFFIX)},
		context.temp_allocator,
	)
	if os.write_entire_file(path, entropy) != nil {
		return ""
	}
	return path
}

// clear_crumb removes the breadcrumb once the case has come back, whatever
// it came back as. Only a case that never returned leaves one.
@(private)
clear_crumb :: proc(path: string) {
	if path != "" {
		os.remove(path)
	}
}

// save_case writes a failing case to the corpus, named for its property and
// its own content so the same case is never written twice.
@(private)
save_case :: proc(
	dir, property: string,
	entropy: []byte,
	allocator := context.allocator,
) -> string {
	if dir == "" {
		return ""
	}
	if err := os.make_directory_all(dir); err != nil && !os.is_dir(dir) {
		return ""
	}
	name := fmt.tprintf("%s-%016x%s", property, fnv(entropy), CASE_SUFFIX)
	path, _ := filepath.join({dir, name}, allocator)
	if os.is_file(path) {
		return path
	}
	if os.write_entire_file(path, entropy) != nil {
		return ""
	}
	return path
}

// fnv hashes a case, for the digest and for naming a saved one.
@(private)
fnv :: proc(b: []byte) -> u64 {
	h := u64(1469598103934665603)
	for c in b {
		h = (h ~ u64(c)) * 1099511628211
	}
	return h
}
