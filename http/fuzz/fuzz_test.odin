package http_fuzz

import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

import harness "jm:fuzz"

// A case's deadline past every wait inside it, enforced by its parent process.
CASE_LIMIT :: 60 * time.Second

// A short run of each suite on fixed seeds, replaying its corpus, so `just
// test` catches a regression without a long fuzz run.
@(test)
wire_holds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	command := smoke_child_command(t, "wire_holds")
	if len(command) == 0 {return}
	for seed in ([]u64{1, 2, 3}) {
		report := run_wire(
			{
				seed = seed, iterations = 60, corpus_dir = WIRE_CORPUS,
				case_timeout = CASE_LIMIT, isolate = true, child_command = command,
				stop_on_first = true, shrink = -1,
			},
		)
		testing.expect_value(t, report.iterations - report.replayed, 60)
		if !expect_clean(t, report) {return}
	}
}

@(test)
model_holds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	command := smoke_child_command(t, "model_holds")
	if len(command) == 0 {return}
	for seed in ([]u64{1, 2, 3}) {
		report := run_model(
			{
				seed = seed, iterations = 30, corpus_dir = MODEL_CORPUS,
				case_timeout = CASE_LIMIT, isolate = true, child_command = command,
				stop_on_first = true, shrink = -1,
			},
		)
		testing.expect_value(t, report.iterations - report.replayed, 30)
		if !expect_clean(t, report) {return}
	}
}

// A socket thread can trap without returning control to the test runner.
// Isolation bounds that case without freeing a server that still has handlers.
// Select only this test in the child: another suite would return an empty report.
// Smoke runs save the original failing entropy and stop; jm-fuzz can replay and
// minimize it later, without retrying a hung case hundreds of times in CI.
smoke_child_command :: proc(t: ^testing.T, name: string) -> []string {
	// odin test supplies only the output basename in argv[0], even when
	// the executable is in build/test and the working directory is the repo.
	self, err := os.get_executable_path(context.temp_allocator)
	if err != nil {
		testing.expectf(t, false, "cannot find this test binary to isolate HTTP cases: %v", err)
		return nil
	}
	command := make([]string, 2, context.temp_allocator)
	command[0], command[1] = self, fmt.tprintf("-tests:http_fuzz.%s", name)
	return command
}

expect_clean :: proc(t: ^testing.T, report: harness.Report) -> bool {
	for f in report.failures {
		testing.expectf(
			t,
			false,
			"%s failed at case %d (replay: jm-fuzz with -seed=%d): %s",
			f.property,
			f.iteration,
			f.seed,
			f.detail,
		)
	}
	return len(report.failures) == 0
}

// Exercise the same native child dispatch as the HTTP smoke tests. A false
// property must reach the parent as a failure, and a blocked one must be killed.
@(test)
smoke_children_report_failure_and_timeout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	command := smoke_child_command(t, "smoke_children_report_failure_and_timeout")
	if len(command) == 0 {return}
	suite := harness.Suite(Subject) {
		name = "http_smoke_guard",
		properties = []harness.Property(Subject){
			{"fails", smoke_failure},
			{"blocks", smoke_blocked},
		},
	}
	r := harness.run(suite, {
		seed = 1, iterations = 2, isolate = true, child_command = command,
		case_timeout = 2 * time.Second, shrink = -1,
	})
	testing.expect_value(t, r.iterations, 2)
	testing.expect_value(t, len(r.failures), 2)
	if len(r.failures) != 2 {return}
	testing.expect_value(t, r.failures[0].outcome, harness.Outcome.Failed)
	testing.expect_value(t, r.failures[0].detail, "HTTP smoke child ran the failing property")
	testing.expect_value(t, r.failures[1].outcome, harness.Outcome.Hung)
	testing.expect(t, r.failures[1].hung, "the parent's deadline must end a blocked child")
}

smoke_failure :: proc(_: Subject, _: ^harness.Source) -> (string, bool) {
	return "HTTP smoke child ran the failing property", false
}

smoke_blocked :: proc(_: Subject, _: ^harness.Source) -> (string, bool) {
	for {time.sleep(time.Second)}
}

@(test)
suites_are_complete :: proc(t: ^testing.T) {
	for s in ([]harness.Suite(Subject){wire_suite(), model_suite()}) {
		testing.expect(t, s.setup != nil && s.teardown != nil, "a case needs a server")
		testing.expect_value(t, len(s.properties), 1)
	}
}
