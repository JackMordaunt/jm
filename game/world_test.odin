package game

import "core:testing"

@(private = "file")
Plain_World :: struct {
	pos:    [2]f32,
	alive:  bool,
	kind:   enum u8 {Ball, Brick},
	flags:  bit_set[0 ..< 8],
	balls:  [dynamic; 8]struct {
		at: [2]f32,
	},
	shape:  union {
		[2]f32,
		f32,
	},
	rng:    Rng,
	name:   [16]u8,
	letter: rune,
}

@(private = "file")
Pointing_World :: struct {
	name:   string,
	inner:  struct {
		next: ^int,
	},
	trail:  [dynamic]f32,
	sprite: union {
		[]u8,
		int,
	},
}

@(test)
plain_data_passes :: proc(t: ^testing.T) {
	problems := check_world(Plain_World, context.temp_allocator)
	testing.expect_value(t, len(problems), 0)
	free_all(context.temp_allocator)
}

@(test)
each_field_that_points_out_is_named :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	problems := check_world(Pointing_World, context.temp_allocator)
	testing.expect_value(t, len(problems), 4)
	if len(problems) == 4 {
		testing.expect_value(t, problems[0], "world.name: string")
		testing.expect_value(t, problems[1], "world.inner.next: ^int")
		testing.expect_value(t, problems[2], "world.trail: [dynamic]f32")
		testing.expect_value(t, problems[3], "world.sprite.([]u8): []u8")
	}
}

@(test)
a_seed_draws_the_same_numbers :: proc(t: ^testing.T) {
	first, second := rng_seed(42), rng_seed(42)
	for _ in 0 ..< 100 {
		testing.expect_value(t, rng_u64(&first), rng_u64(&second))
	}
	other := rng_seed(43)
	testing.expect(t, rng_u64(&first) != rng_u64(&other))
	for _ in 0 ..< 1000 {
		fraction := rng_float(&first)
		testing.expect(t, fraction >= 0 && fraction < 1)
		drawn := rng_int(&first, 3, 7)
		testing.expect(t, drawn >= 3 && drawn < 7)
	}
}
