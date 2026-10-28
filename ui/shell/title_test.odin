package shell

import "core:testing"
import "jm:ui/ops"

@(test)
test_title_hit_edges_buttons_and_drags :: proc(t: ^testing.T) {
	client := ops.Size{800, 600}
	buttons := ops.Rect{700, 0, 90, 30}
	border: f32 = 8
	drags := []ops.Rect{{0, 0, 700, 30}}

	testing.expect_value(t, title_hit({400, 100}, client, buttons, border, drags, false), Title_Hit.Client)
	testing.expect_value(t, title_hit({100, 16}, client, buttons, border, drags, false), Title_Hit.Caption)
	testing.expect_value(t, title_hit({100, 8}, client, buttons, border, drags, false), Title_Hit.Caption)
	testing.expect_value(t, title_hit({100, 2}, client, buttons, border, drags, false), Title_Hit.Top)
	testing.expect_value(t, title_hit({2, 2}, client, buttons, border, drags, false), Title_Hit.Top_Left)
	testing.expect_value(t, title_hit({796, 2}, client, buttons, border, drags, false), Title_Hit.Top_Right)

	testing.expect_value(t, title_hit({705, 10}, client, buttons, border, drags, false), Title_Hit.Minimize)
	testing.expect_value(t, title_hit({740, 10}, client, buttons, border, drags, false), Title_Hit.Maximize)
	testing.expect_value(t, title_hit({770, 10}, client, buttons, border, drags, false), Title_Hit.Close)
	testing.expect_value(t, title_hit({790, 30}, client, buttons, border, drags, false), Title_Hit.Close)
	// The top strip over the close button is the button, not a resize.
	testing.expect_value(t, title_hit({790, 2}, client, buttons, border, drags, false), Title_Hit.Close)

	testing.expect_value(t, title_hit({705, 10}, client, buttons, border, drags, true), Title_Hit.Close)
	testing.expect_value(t, title_hit({740, 10}, client, buttons, border, drags, true), Title_Hit.Maximize)
	testing.expect_value(t, title_hit({770, 10}, client, buttons, border, drags, true), Title_Hit.Minimize)

	testing.expect_value(t, title_hit({2, 2}, client, buttons, 0, drags, false), Title_Hit.Caption)

	over := []ops.Rect{{0, 0, 800, 40}}
	testing.expect_value(t, title_hit({740, 10}, client, buttons, border, over, false), Title_Hit.Maximize)
	// An empty button rect claims nothing, so the drag under it is the caption.
	// The resize strip still wins over that drag.
	testing.expect_value(t, title_hit({740, 10}, client, {}, border, over, false), Title_Hit.Caption)
	testing.expect_value(t, title_hit({740, 2}, client, {}, border, over, false), Title_Hit.Top)
}

@(test)
test_title_button_pixels_covers_the_caption_buttons :: proc(t: ^testing.T) {
	w: Window
	testing.expect_value(t, title_button_pixels(&w, 80, 40), ops.Rect{})

	w.title_on = true
	w.buttons_px = {2, 1, 3, 2}
	testing.expect_value(t, title_button_pixels(&w, 80, 40), ops.Rect{2, 1, 3, 2})

	w.buttons_px = {0.2, 0.8, 1.1, 1.1}
	testing.expect_value(t, title_button_pixels(&w, 80, 40), ops.Rect{0, 0, 2, 2})

	w.buttons_px = {-4, -2, 6, 5}
	testing.expect_value(t, title_button_pixels(&w, 8, 4), ops.Rect{0, 0, 2, 3})

	w.buttons_px = {70, 30, 40, 20}
	testing.expect_value(t, title_button_pixels(&w, 80, 40), ops.Rect{70, 30, 10, 10})

	w.title_on = false
	testing.expect_value(t, title_button_pixels(&w, 80, 40), ops.Rect{})
}

@(test)
test_title_set_drags_publishes_one_slot :: proc(t: ^testing.T) {
	w: Window
	title_set_drags(&w, []ops.Rect{{1, 2, 3, 4}, {5, 6, 7, 8}})
	testing.expect_value(t, w.drag_read, 1)
	testing.expect_value(t, w.drag_n[1], 2)
	testing.expect_value(t, w.drags[1][0], ops.Rect{1, 2, 3, 4})

	title_set_drags(&w, nil)
	testing.expect_value(t, w.drag_read, 0)
	testing.expect_value(t, w.drag_n[0], 0)
	testing.expect_value(t, w.drags[1][0], ops.Rect{1, 2, 3, 4})

	many: [TITLE_DRAG_CAP + 1]ops.Rect
	for i in 0 ..< len(many) {
		many[i] = {f32(i), 0, 1, 1}
	}
	title_set_drags(&w, many[:])
	testing.expect_value(t, w.drag_n[w.drag_read], TITLE_DRAG_CAP)
	testing.expect_value(t, w.drags[w.drag_read][TITLE_DRAG_CAP - 1], ops.Rect{f32(TITLE_DRAG_CAP - 1), 0, 1, 1})
}
