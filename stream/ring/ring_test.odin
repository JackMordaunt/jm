package ring

import "core:testing"
import "core:thread"

// The layout is the point: the two ends on separate lines, the storage and
// sizes on neither.
@(test)
ends_sit_on_their_own_lines :: proc(t: ^testing.T) {
	producer := offset_of(Raw, tail)
	consumer := offset_of(Raw, head)
	shared_end := offset_of(Raw, cap) + size_of(int)
	testing.expect(t, consumer - producer >= LINE, "head and tail share a line")
	testing.expect(t, producer - shared_end >= LINE, "tail shares a line with the storage fields")
	testing.expect(t, offset_of(Raw, shape) < producer, "the shape is not with the storage fields")
	testing.expect(t, offset_of(Raw, head_seen) - producer < LINE, "head_seen is not on the producer's line")
	testing.expect(t, offset_of(Raw, pushed) - producer < LINE, "pushed is not on the producer's line")
	testing.expect(t, offset_of(Raw, tail_seen) - consumer < LINE, "tail_seen is not on the consumer's line")
	testing.expect(t, offset_of(Raw, popped) - consumer < LINE, "popped is not on the consumer's line")
	testing.expect(t, size_of(Raw) - consumer >= LINE, "the consumer's line runs into whatever follows")
}

@(test)
wraps_and_reports_full_and_empty :: proc(t: ^testing.T) {
	r := make_ring(int, 3, context.allocator)
	defer destroy_ring(&r, context.allocator)
	for round in 0 ..< 5 {
		testing.expect(t, !has(&r.raw))
		testing.expect(t, push_value(&r, round * 10 + 1))
		testing.expect(t, push_value(&r, round * 10 + 2))
		testing.expect(t, push_value(&r, round * 10 + 3))
		testing.expect(t, full(&r.raw))
		testing.expect(t, !push_value(&r, 99), "a full ring refuses")
		testing.expect_value(t, len(&r.raw), 3)
		for want in 1 ..= 3 {
			v, ok := pop_value(&r)
			testing.expect(t, ok)
			testing.expect_value(t, v, round * 10 + want)
		}
		_, ok := pop_value(&r)
		testing.expect(t, !ok, "an empty ring gives nothing")
	}
	testing.expect_value(t, r.pushed, 15)
	testing.expect_value(t, r.popped, 15)
}

Blob :: struct {
	bytes: [200]u8,
	tag:   int,
}

@(test)
carries_zero_and_large_messages :: proc(t: ^testing.T) {
	none := make_ring(struct {}, 2, context.allocator)
	defer destroy_ring(&none, context.allocator)
	testing.expect(t, push_value(&none, struct {}{}))
	testing.expect(t, push_value(&none, struct {}{}))
	testing.expect(t, full(&none.raw))
	_, ok := pop_value(&none)
	testing.expect(t, ok)

	big := make_ring(Blob, 2, context.allocator)
	defer destroy_ring(&big, context.allocator)
	b: Blob
	b.tag = 7
	b.bytes[199] = 9
	testing.expect(t, push_value(&big, b))
	got, ok2 := pop_value(&big)
	testing.expect(t, ok2)
	testing.expect_value(t, got.tag, 7)
	testing.expect_value(t, got.bytes[199], u8(9))
}

Producer :: struct {
	r:     ^Ring(int),
	count: int,
}

produce :: proc(p: ^Producer) {
	for ii in 0 ..< p.count {
		for !push_value(p.r, ii) {}
	}
}

// One thread pushes a million in order through a small ring while another
// pops; every value arrives once, in order. Run under -sanitize:thread to
// check the two ends never race.
@(test)
one_producer_one_consumer_across_threads :: proc(t: ^testing.T) {
	r := make_ring(int, 8, context.allocator)
	defer destroy_ring(&r, context.allocator)
	count := 1_000_000
	p := Producer{&r, count}
	th := thread.create_and_start_with_poly_data(&p, produce)
	next := 0
	for next < count {
		v, ok := pop_value(&r)
		if !ok {
			continue
		}
		if v != next {
			testing.expectf(t, false, "got %d, expected %d", v, next)
			break
		}
		next += 1
	}
	thread.join(th)
	thread.destroy(th)
	testing.expect_value(t, next, count)
	testing.expect_value(t, len(&r.raw), 0)
}

Wide :: struct #align (32) {
	b: [40]u8,
}

@(test)
shape_carries_size_alignment_and_type :: proc(t: ^testing.T) {
	sh := shape_of(Wide)
	testing.expect_value(t, sh.size, 64)
	testing.expect_value(t, sh.align, 32)
	testing.expect(t, sh.id == Wide)
	testing.expect(t, shape_of(int) != shape_of(f64), "same size, different type")
	testing.expect_value(t, shape_of(struct {}).size, 0)
}

// Every slot of an over-aligned message type sits on its alignment.
@(test)
storage_honours_the_alignment :: proc(t: ^testing.T) {
	r := make_ring(Wide, 5, context.allocator)
	defer destroy_ring(&r, context.allocator)
	for ii in 0 ..< 5 {
		w: Wide
		w.b[39] = u8(ii)
		testing.expect(t, push_value(&r, w))
		slot := uintptr(&r.data[ii * r.shape.size])
		testing.expect(t, slot % 32 == 0, "a slot is off its alignment")
	}
	for ii in 0 ..< 5 {
		w, ok := pop_value(&r)
		testing.expect(t, ok)
		testing.expect_value(t, w.b[39], u8(ii))
	}
}
