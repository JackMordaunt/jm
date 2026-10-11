package game

// Rng is a seeded random number generator kept in the World, so a run's
// randomness is part of its state: a snapshot copies it, and a replay from
// the same seed draws the same numbers. It is SplitMix64
// (https://prng.di.unimi.it/splitmix64.c): one u64 of state, fast, and
// good enough for games. A game draws from no other source in step.
Rng :: struct {
	state: u64,
}

// rng_seed returns a generator that starts from seed.
rng_seed :: proc(seed: u64) -> Rng {
	return {state = seed}
}

// rng_u64 draws 64 random bits.
rng_u64 :: proc(rng: ^Rng) -> u64 {
	rng.state += 0x9e3779b97f4a7c15
	mixed := rng.state
	mixed = (mixed ~ (mixed >> 30)) * 0xbf58476d1ce4e5b9
	mixed = (mixed ~ (mixed >> 27)) * 0x94d049bb133111eb
	return mixed ~ (mixed >> 31)
}

// rng_float draws a float in [0, 1).
rng_float :: proc(rng: ^Rng) -> f32 {
	return f32(rng_u64(rng) >> 40) / f32(1 << 24)
}

// rng_int draws an int in [lo, hi); lo when the range is empty.
rng_int :: proc(rng: ^Rng, lo, hi: int) -> int {
	if hi <= lo {
		return lo
	}
	return lo + int(rng_u64(rng) % u64(hi - lo))
}
