package i18n_store

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_a_setting_survives_reopening :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("", "atlas-store-*", context.allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	defer delete(dir)
	path, _ := filepath.join({dir, "atlas.db"}, context.temp_allocator)
	defer free_all(context.temp_allocator)

	st: Store
	testing.expect(t, open(&st, path))
	_, found := setting(&st, LANGUAGE, context.temp_allocator)
	testing.expect(t, !found)
	testing.expect(t, set_setting(&st, LANGUAGE, "de"))
	testing.expect(t, set_setting(&st, LANGUAGE, "pt-BR"))
	close(&st)

	testing.expect(t, open(&st, path))
	defer close(&st)
	value: string
	value, found = setting(&st, LANGUAGE, context.temp_allocator)
	testing.expect(t, found)
	testing.expect_value(t, value, "pt-BR")
}
