package prelude

import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
failed_shapes :: proc(t: ^testing.T) {
	testing.expect(t, !failed(os.Error(nil)))
	testing.expect(t, failed(os.Error(os.General_Error.Not_Exist)))
	testing.expect(t, !failed(mem.Allocator_Error.None))
	testing.expect(t, failed(mem.Allocator_Error.Out_Of_Memory))
	testing.expect(t, !failed(""))
	testing.expect(t, failed("boom"))
	p: ^int
	testing.expect(t, !failed(p))
}

@(test)
must_passes_values_through :: proc(t: ^testing.T) {
	testing.expect_value(t, must(42, true), 42)
	testing.expect_value(t, must("s", os.Error(nil)), "s")
	must(true)
	must(os.Error(nil))
}

@(test)
logfmt_quoting :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	write_quoted(&b, "say \"hi\"\n\\")
	testing.expect_value(t, strings.to_string(b), `"say \"hi\"\n\\"`)
}

@(test)
env_default :: proc(t: ^testing.T) {
	testing.expect_value(t, env("JFM_PRELUDE_UNSET_3F9A", "fallback", context.temp_allocator), "fallback")
	testing.expect_value(t, level_name(.Warning), "warning")
}
