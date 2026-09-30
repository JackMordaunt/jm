package main

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(private = "file")
DOC :: `{
	"source": {"commit": "abc", "file": "LoadingIndicator.kt"},
	"indeterminate": {
		"sequence": ["a", "b"], "circular": true,
		"shapesScaleFactor": 0.5, "activeIndicatorScale": 0.75, "drawScale": 0.375,
		"pairs": [{"from": "a", "to": "b", "start": [[0, 0, 1, 0, 1, 1, 0, 1]], "end": [[1, 1, 0, 1, 0, 0, 1, 0.25]]}]
	},
	"determinate": {
		"sequence": ["c", "d"], "circular": false,
		"shapesScaleFactor": 1, "activeIndicatorScale": 0.5, "drawScale": 0.5,
		"pairs": [{"from": "c", "to": "d", "start": [[0, 0, 0, 0, 0, 0, 0, 0]], "end": [[1, 1, 1, 1, 1, 1, 1, 1]]}]
	}
}`

@(test)
test_generate_writes_both_sequences_with_their_scales :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(transmute([]u8)string(DOC))
	testing.expect_value(t, err, json.Error.None)
	out, ok := generate(doc.(json.Object))
	testing.expect(t, ok)
	for want in ([]string {
			"LOADING_INDETERMINATE := Loading_Sequence {",
			"from = \"a\",\n\t\t\tto = \"b\",",
			"{1, 1, 0, 1, 0, 0, 1, 0.25},",
			"circular = true,",
			"draw_scale = 0.375,",
			"LOADING_DETERMINATE := Loading_Sequence {",
			"circular = false,",
			"active_indicator_scale = 0.5,",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
}

@(test)
test_generate_refuses_a_pair_of_unequal_length :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	// The document is fine until one pair loses its end.
	good, _ := json.parse(transmute([]u8)string(DOC))
	_, ok := generate(good.(json.Object))
	testing.expect(t, ok)
	bad, _ := strings.replace(DOC, `"end": [[1, 1, 0, 1, 0, 0, 1, 0.25]]`, `"end": []`, 1)
	doc, _ := json.parse(transmute([]u8)bad)
	_, ok = generate(doc.(json.Object))
	testing.expect(t, !ok)
}

@(test)
test_the_checked_in_shape_data_is_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(#load("../shapes/morphs.json"))
	testing.expect(t, err == json.Error.None)
	out, ok := generate(doc.(json.Object))
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../../ui/material/shape_data.odin")),
		"ui/material/shape_data.odin is stale; run just material-shapes",
	)
}
