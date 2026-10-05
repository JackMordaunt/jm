package files_placement

import "core:path/filepath"
import "core:testing"

@(test)
method_of_each_paste :: proc(t: ^testing.T) {
	S :: filepath.SEPARATOR_STRING
	cases := []struct {
		name: string,
		f:    Facts,
		want: Method,
	} {
		{"folder into itself", {source = S + "a", dest = S + "a", mode = .Move, source_is_dir = true}, .Into_Itself},
		{"folder into its child", {source = S + "a", dest = S + "a" + S + "b", mode = .Copy, source_is_dir = true}, .Into_Itself},
		{"a sibling with a longer name is not inside", {source = S + "a", dest = S + "ab", mode = .Move, source_is_dir = true, same_volume = true}, .Rename},
		{"move where it is", {source = S + "a" + S + "f", dest = S + "a", mode = .Move}, .Already_There},
		{"copy where it is", {source = S + "a" + S + "f", dest = S + "a", mode = .Copy, name_taken = true}, .Duplicate},
		{"name taken", {source = S + "a" + S + "f", dest = S + "b", mode = .Move, same_volume = true, name_taken = true}, .Conflict},
		{"move on one volume", {source = S + "a" + S + "f", dest = S + "b", mode = .Move, same_volume = true}, .Rename},
		{"move across volumes", {source = S + "a" + S + "f", dest = S + "b", mode = .Move}, .Copy_Then_Trash},
		{"copy", {source = S + "a" + S + "f", dest = S + "b", mode = .Copy, same_volume = true}, .Copy},
	}
	for c in cases {
		got := method(c.f)
		testing.expectf(t, got == c.want, "%s: %v, want %v", c.name, got, c.want)
	}
}
