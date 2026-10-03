package fuzz

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "jm:path"

/*
Isolation runs each case in a child process instead of in this one.

It costs a spawn per case, an order of magnitude slower than running them
here; docs/fuzzing.md records the measurement. What it buys is that nothing a
property does can end the run: a panic, a failed bounds check, a corrupted
heap and a loop that never finishes all come back as one more result, with
the case that caused it, and the next case starts from a clean process.

It also makes the deadline work for any subject at all. In this process a
case can only be cut short if its suite supplies cancel; a child is killed
whether it cooperates or not, so a suite over a parser with no interruption
point gets a deadline for free.

The child is this same binary, re-run with the case named in its environment.
run notices those variables before it does anything else and serves the one
case, so a program that calls run needs no extra wiring to be its own child.
*/

// ENV_CASE names the case a child is to run, as "<suite>/<property>".
ENV_CASE :: "JM_FUZZ_CASE"
// ENV_ENTROPY is the file the child reads its case's bytes from.
ENV_ENTROPY :: "JM_FUZZ_ENTROPY"
// ENV_DETAIL is the file the child writes its failure detail to.
ENV_DETAIL :: "JM_FUZZ_DETAIL"

// EXIT_FAILED says the property was checked and did not hold. Any other
// non-zero exit, or a signal, is the child dying rather than reporting.
EXIT_FAILED :: 70
// EXIT_BROKEN says the child could not run the case it was given at all.
EXIT_BROKEN :: 71

// Outcome is what became of one case.
Outcome :: enum {
	// The property held.
	Held,
	// The property was checked and did not hold.
	Failed,
	// The case ended the process: a panic, a bounds check, a signal.
	Crashed,
	// The case did not finish inside the deadline and was killed.
	Hung,
	// The case could not be run, which is a fault in the harness or the
	// suite rather than in what is being tested.
	Broken,
}

// Isolation is what a run needs to spawn its own children.
@(private)
Isolation :: struct {
	command: []string,
	env:     []string,
	work:    string,
	entropy: string,
	detail:  string,
	output:  string,
}

// start_isolation prepares the work files and the command a child is spawned
// with. An empty command means this binary.
@(private)
start_isolation :: proc(
	command: []string,
	allocator := context.allocator,
) -> (
	iso: ^Isolation,
	err: string,
) {
	iso = new(Isolation, allocator)
	iso.command = command
	if len(iso.command) == 0 {
		self, aerr := filepath.abs(os.args[0], allocator)
		if aerr != nil {
			return nil, "cannot find this binary to re-run it"
		}
		one := make([]string, 1, allocator)
		one[0] = self
		iso.command = one
	}

	parent := os.temp_directory(allocator) or_else ""
	work, derr := os.make_directory_temp(parent, "jm-fuzz-*", allocator)
	if derr != nil {
		return nil, fmt.tprintf("cannot make a work directory: %v", derr)
	}
	iso.work = work
	iso.entropy, _ = filepath.join({work, "entropy"}, allocator)
	iso.detail, _ = filepath.join({work, "detail"}, allocator)
	iso.output, _ = filepath.join({work, "output"}, allocator)

	// The child is told which case to run through the environment, so the
	// rest of it is inherited as it stands.
	base, eerr := os.environ(allocator)
	if eerr != nil {
		base = nil
	}
	iso.env = base
	return iso, ""
}

@(private)
stop_isolation :: proc(iso: ^Isolation) {
	if iso != nil && iso.work != "" {
		os.remove_all(iso.work)
	}
}

// run_isolated runs one case in a child and waits for it. It knows nothing
// about the subject type, which is the point: everything that can go wrong
// in the child comes back as an Outcome.
@(private)
run_isolated :: proc(
	iso: ^Isolation,
	suite, property: string,
	entropy: []byte,
	timeout: time.Duration,
	allocator := context.allocator,
) -> (
	detail: string,
	outcome: Outcome,
) {
	if os.write_entire_file(iso.entropy, entropy) != nil {
		return "cannot write the case for the child", .Broken
	}
	// Left over detail from the case before would be read as this one's.
	os.remove(iso.detail)

	out, oerr := os.open(iso.output, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if oerr != nil {
		return fmt.tprintf("cannot capture the child's output: %v", oerr), .Broken
	}

	env := make([dynamic]string, 0, len(iso.env) + 3, context.temp_allocator)
	append(&env, ..iso.env)
	append(&env, fmt.tprintf("%s=%s/%s", ENV_CASE, suite, property))
	append(&env, fmt.tprintf("%s=%s", ENV_ENTROPY, iso.entropy))
	append(&env, fmt.tprintf("%s=%s", ENV_DETAIL, iso.detail))

	// Only stderr is kept. A child that is itself a fuzz tool writes its own
	// progress to stdout, and that would be read back as part of whatever
	// the case did.
	child, serr := os.process_start(
		os.Process_Desc{command = iso.command, env = env[:], stdout = nil, stderr = out},
	)
	if serr != nil {
		os.close(out)
		return fmt.tprintf("cannot start a child: %v", serr), .Broken
	}

	state, werr := os.process_wait(child, timeout)
	killed := false
	if werr == os.General_Error.Timeout {
		_ = os.process_kill(child)
		state, werr = os.process_wait(child)
		killed = true
	}
	os.close(out)

	outcome = classify(state, werr, killed)
	switch outcome {
	case .Failed:
		detail = read_text(iso.detail, allocator)
		if detail == "" {
			detail = "the property failed but said nothing"
		}
	case .Crashed:
		said := read_text(iso.output, allocator)
		detail = fmt.aprintf(
			"the case ended the process (%s)%s",
			describe(state, werr),
			said != "" ? fmt.tprintf(": %s", shorten(said)) : "",
			allocator = allocator,
		)
	case .Hung:
		detail = fmt.aprintf(
			"did not finish within %v, and was killed",
			timeout,
			allocator = allocator,
		)
	case .Broken:
		detail = fmt.aprintf(
			"the child could not run the case (%s)",
			describe(state, werr),
			allocator = allocator,
		)
	case .Held:
	}
	return detail, outcome
}

// classify reads what the operating system said about the child. It is kept
// apart from the spawning so it can be checked on its own.
@(private)
classify :: proc(state: os.Process_State, err: os.Error, killed: bool) -> Outcome {
	if killed {
		return .Hung
	}
	if err != nil {
		return .Broken
	}
	if !state.exited {
		return .Crashed
	}
	switch state.exit_code {
	case 0:
		// A process that exited zero but is reported unsuccessful is a
		// contradiction; trust the exit code, which is what the child sets
		// deliberately.
		return .Held
	case EXIT_FAILED:
		return .Failed
	case EXIT_BROKEN:
		return .Broken
	}
	return .Crashed
}

// describe says how the child ended, for a report a person will read.
@(private)
describe :: proc(state: os.Process_State, err: os.Error) -> string {
	if err != nil {
		return fmt.tprintf("could not be waited for: %v", err)
	}
	if !state.exited {
		return "still running"
	}
	if !state.success {
		return fmt.tprintf("signal or exception %d", state.exit_code)
	}
	return fmt.tprintf("exit %d", state.exit_code)
}

// serve_one runs the single case named in the environment and never returns,
// unless the case belongs to another suite in the same binary.
@(private)
serve_one :: proc(suite: Suite($S), spec: string) -> (mine: bool) {
	slash := strings.last_index_byte(spec, '/')
	if slash <= 0 {
		os.exit(EXIT_BROKEN)
	}
	if spec[:slash] != suite.name {
		return false
	}
	property := spec[slash + 1:]

	which := -1
	for p, i in suite.properties {
		if p.name == property {
			which = i
		}
	}
	if which < 0 {
		os.exit(EXIT_BROKEN)
	}

	path, found := os.lookup_env(ENV_ENTROPY, context.allocator)
	if !found {
		os.exit(EXIT_BROKEN)
	}
	entropy, rerr := os.read_entire_file_from_path(path, context.allocator)
	if rerr != nil {
		os.exit(EXIT_BROKEN)
	}

	// No watchdog and no isolation here: the parent holds the deadline, and
	// a child that spawned its own children would fork for ever.
	dog := new(Watchdog, context.allocator)
	detail, ok, _ := attempt(suite, which, entropy, dog, TIMEOUT_NONE, nil, nil)
	if ok {
		os.exit(0)
	}
	if out, found_out := os.lookup_env(ENV_DETAIL, context.allocator); found_out {
		_ = os.write_entire_file(out, transmute([]byte)detail)
	}
	os.exit(EXIT_FAILED)
}

// TIMEOUT_NONE is the deadline a child runs under: none of its own.
@(private)
TIMEOUT_NONE :: time.Duration(0)

// read_text reads a file the child wrote, or "" if it wrote none. A child
// that said nothing is the ordinary case, not an error worth reporting.
@(private)
read_text :: proc(name: string, allocator := context.allocator) -> string {
	text, err := path.read(name, allocator)
	return err == nil ? text : ""
}

// shorten keeps a child's output short enough to read in a report.
@(private)
shorten :: proc(s: string) -> string {
	out := strings.trim_space(s)
	if len(out) > 400 {
		return fmt.tprintf("%s...", out[:400])
	}
	return out
}
