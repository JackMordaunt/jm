/*
Package fuzz holds the jm:ui/datagrid suites for jm:fuzz: the grid's pure
model checked against references written the plain way, and a paged grid
driven through ui.Probe against a host that answers out of order.

	report := fuzz.run_model({seed = 1, iterations = 1000})
	report  = fuzz.run_paged({seed = 1, iterations = 1000})

	ui_datagrid        widths     the width solver keeps every bound and
	                              fills or fits as its Fit says
	                   heights    the Fenwick index agrees with prefix sums
	                              and finds the row at every y
	                   selection  ops on a Selection agree with a set model
	                   query      order_build agrees with filtering and a
	                              stable sort written the plain way, and
	                              filters compose as an intersection
	                   pages      the page cache shows only the current
	                              query's rows as Ready, stays bounded and
	                              finds the end
	                   delimited  CSV and TSV read back as written through
	                              an RFC 4180 reader
	                   views      a view reads back as it was written, and
	                              against changed columns stays whole
	ui_datagrid_paged  paged      random scrolls, sorts, filters, searches
	                              and clicks against pages that arrive out
	                              of order, failed, stale, late or never:
	                              no row shows under the wrong query, the
	                              cache and the need set stay bounded, and
	                              the selection stays keyed

A case is a pure function of its bytes: the probe runs on the stub shaper
and the host's choices are drawn like everything else.
*/
package datagrid_fuzz

import harness "jm:fuzz"

// Nothing is the suites' subject: each case builds what it checks.
Nothing :: struct {}

model_properties := []harness.Property(Nothing) {
	{"widths", widths},
	{"heights", heights},
	{"selection", selection},
	{"query", query},
	{"pages", pages},
	{"delimited", delimited},
	{"views", views},
}

paged_properties := []harness.Property(Nothing){{"paged", paged}}

// The corpora, relative to the repository root.
MODEL_CORPUS :: "ui/datagrid/fuzz/corpus/model"
PAGED_CORPUS :: "ui/datagrid/fuzz/corpus/paged"

model_suite :: proc() -> harness.Suite(Nothing) {
	return harness.Suite(Nothing) {
		name = "ui_datagrid",
		setup = setup,
		properties = model_properties,
	}
}

paged_suite :: proc() -> harness.Suite(Nothing) {
	return harness.Suite(Nothing) {
		name = "ui_datagrid_paged",
		setup = setup,
		properties = paged_properties,
	}
}

// run_model checks the pure model's suite.
run_model :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(model_suite(), opts, allocator)
}

// run_paged checks the paged grid's suite.
run_paged :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(paged_suite(), opts, allocator)
}

@(private)
setup :: proc() -> (Nothing, bool) {
	return {}, true
}
