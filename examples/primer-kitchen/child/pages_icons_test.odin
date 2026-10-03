package main

import "core:testing"
import "jm:ui/primer"

@(test)
fuzzy_match_finds_subsequences :: proc(t: ^testing.T) {
	testing.expect(t, fuzzy_match("arrow-down", ""))
	testing.expect(t, fuzzy_match("arrow-down", "arwdn"))
	testing.expect(t, fuzzy_match("arrow-down", "Arrow Down"))
	testing.expect(t, fuzzy_match("arrow-down", "arrow-down"))
	testing.expect(t, !fuzzy_match("arrow-down", "down arrow"))
	testing.expect(t, !fuzzy_match("arrow-down", "arrow-downs"))
	testing.expect(t, !fuzzy_match("", "a"))
}

@(test)
icons_seed_names_and_sorts_every_icon :: proc(t: ^testing.T) {
	ic := new(Icons)
	defer {
		for n in ic.sorted {
			delete(n.name)
		}
		free(ic)
	}
	icons_seed(ic)
	seen: [primer.Icon]bool
	for n, i in ic.sorted {
		testing.expect(t, n.icon != .None)
		testing.expect(t, !seen[n.icon], "an icon appears twice")
		seen[n.icon] = true
		if i > 0 {
			testing.expectf(t, ic.sorted[i - 1].name < n.name, "%s sorts before %s", ic.sorted[i - 1].name, n.name)
		}
	}
	testing.expect_value(t, ic.sorted[9].name, "arrow-down")
	testing.expect_value(t, ic.sorted[9].icon, primer.Icon.Arrow_Down)
}
