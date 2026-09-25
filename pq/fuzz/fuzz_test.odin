package pq_fuzz

import "core:log"
import "core:testing"

import harness "jm:fuzz"
import "jm:pq/testdb"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run, and replays the corpus. Long runs are
// `just fuzz pq`. Without a server it skips, as jm:pq's own tests do.
@(test)
properties_hold :: proc(t: ^testing.T) {
	//review:ignore skips-in-normal-conditions the spec asks for a skip, not a failure, where initdb is not installed: testdb brings its own server up, so this skips only on a machine without the PostgreSQL server package, and `just test` must stay green there; the skip is logged
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to fuzz against: %s", why)
		return
	}
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 150, corpus_dir = CORPUS})
		testing.expect(t, report.iterations >= 150, "every case must run")
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz pq -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "pq")
	testing.expect(t, s.setup != nil, "a case needs a connection")
	testing.expect(t, s.teardown != nil, "a case must give it back")
	testing.expect(
		t,
		s.cancel == nil,
		"statement_timeout bounds a case; PQcancel is not bound for the suite's sake",
	)
	testing.expect(t, len(s.properties) == 6, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// A run is a pure function of its seed, so a failure replays exactly.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	//review:ignore skips-in-normal-conditions as properties_hold: skips only where initdb is not installed, and says so
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to fuzz against: %s", why)
		return
	}
	context.allocator = context.temp_allocator
	first := run({seed = 42, iterations = 60})
	second := run({seed = 42, iterations = 60})
	testing.expect_value(t, first.iterations, 60)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)
}

// A zero source draws the simplest case of each generator, which is what
// shrinking converges on.
@(test)
zero_source_is_simplest :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	src := harness.source(nil)
	sql, from := statement(&src)
	testing.expect_value(t, from, Origin.Generated)
	testing.expect_value(t, sql, "SELECT 1")
	src = harness.source(nil)
	testing.expect_value(t, value(&src), "")
}
