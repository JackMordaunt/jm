package ui

import "core:os"
import "core:testing"

@(test)
test_debug_from_env_reads_jm_ui_reveal :: proc(t: ^testing.T) {
	defer os.unset_env(DEBUG_REVEAL_ENV)
	os.unset_env(DEBUG_REVEAL_ENV)
	testing.expect_value(t, debug_from_env(), Debug_Flags{})
	os.set_env(DEBUG_REVEAL_ENV, "1")
	testing.expect_value(t, debug_from_env(), Debug_Flags{.Reveal})
	os.set_env(DEBUG_REVEAL_ENV, "0")
	testing.expect_value(t, debug_from_env(), Debug_Flags{})
}
