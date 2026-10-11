package game

import "core:testing"

@(private = "file")
State :: enum u8 {
	Standing,
	Jumping,
}

@(private = "file")
Circle :: struct {
	radius: f32,
}

@(private = "file")
Hp :: enum u8 {
	Player,
	Boss,
}

@(private = "file")
Arena :: struct {
	player: struct {
		at:    [2]f32,
		state: State,
		name:  [8]u8,
	},
	sparks: [dynamic; 4]struct {
		at:  [2]f32,
		hot: bool,
	},
	tiles:  [6]u8,
	hits:   [Hp]struct {
		left: i32,
	},
	shape:  union {
		Circle,
		f32,
	},
	keys:   bit_set[State],
}

@(private = "file")
arena :: proc() -> (world: Arena) {
	world.player.at = {12, 40}
	world.player.state = .Jumping
	copy(world.player.name[:], "Ann")
	append(&world.sparks, type_of(world.sparks[0]){at = {3.5, 40}, hot = true})
	world.tiles = {1, 1, 0, 2, 0, 0}
	world.hits[.Boss].left = 9
	world.shape = Circle{4}
	world.keys = {.Jumping}
	return
}

@(test)
a_dump_is_a_line_a_value_under_its_path :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	world := arena()
	testing.expect_value(
		t,
		dump_world(&world, context.temp_allocator),
		`player.at = [12, 40]
player.state = Jumping
player.name = "Ann"
sparks.len = 1
sparks[0].at = [3.5, 40]
sparks[0].hot = true
tiles = [1, 1, 0, 2, 0, 0]
hits[.Player].left = 0
hits[.Boss].left = 9
shape.(Circle).radius = 4
keys = {Jumping}
`,
	)
}

@(test)
a_diff_names_only_what_changed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	before := arena()
	after := before
	testing.expect_value(t, diff_world(&before, &after, context.temp_allocator), "")

	after.player.at.y = 38
	after.player.state = .Standing
	append(&after.sparks, type_of(after.sparks[0]){at = {5, 40}})
	after.shape = f32(2)
	testing.expect_value(
		t,
		diff_world(&before, &after, context.temp_allocator),
		`player.at: [12, 40] -> [12, 38]
player.state: Jumping -> Standing
sparks.len: 1 -> 2
sparks[1].at: - -> [5, 40]
sparks[1].hot: - -> false
shape.(f32): - -> 2
shape.(Circle).radius: 4 -> -
`,
	)
}

@(test)
a_value_is_found_by_its_path :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	world := arena()
	value, ok := world_value(&world, "hits[.Boss].left", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, value, "9")
	_, ok = world_value(&world, "player.speed", context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
a_watch_speaks_only_when_its_value_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	world := arena()
	watch: Watch
	watch_init(&watch, "player")
	defer watch_destroy(&watch)

	line, changed := watch_check(&watch, &world, 0)
	testing.expect(t, changed)
	testing.expect_value(t, line, "tick 0 player.at: [12, 40]\ntick 0 player.state: Jumping\ntick 0 player.name: \"Ann\"")
	world.sparks[0].hot = false // not under player
	_, changed = watch_check(&watch, &world, 1)
	testing.expect(t, !changed)
	world.player.state = .Standing
	line, changed = watch_check(&watch, &world, 2)
	testing.expect(t, changed)
	testing.expect_value(t, line, "tick 2 player.state: Jumping -> Standing")

	// A path is watched whole: "player.at" is not "player.attack".
	testing.expect(t, under("player.at", "player.at"))
	testing.expect(t, under("sparks[0].at", "sparks"))
	testing.expect(t, !under("player.attack", "player.at"))
}
