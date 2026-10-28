#+build !windows
package shell

import "jm:ui"

// Unified is implemented on Windows. Attaching succeeds and the frame
// reports no title bar, so a caller that sets the mode still runs.
@(private)
title_attach :: proc(_: ^Window) -> bool {
	return true
}

@(private)
title_detach :: proc(_: ^Window) {}

@(private)
title_metrics :: proc(_: ^Window) -> ui.Title_Bar {
	return {}
}
