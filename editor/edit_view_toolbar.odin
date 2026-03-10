package editor

import rl "vendor:raylib"

// EDIT_TOOLBAR_H is the height of the toolbar at the top of the Edit View panel.
EDIT_TOOLBAR_H :: f32(32)

// edit_view_aabb_toolbar_rects returns the five AABB/BVH toolbar button rects so draw and update share one definition.
edit_view_aabb_toolbar_rects :: proc(content: rl.Rectangle) -> (btn_aabb, btn_sel, btn_bvh, btn_d_plus, btn_d_minus: rl.Rectangle) {
	btn_aabb    = rl.Rectangle{content.x + 278, content.y + 5, 44, 22}
	btn_sel     = rl.Rectangle{content.x + 324, content.y + 5, 28, 22}
	btn_bvh     = rl.Rectangle{content.x + 354, content.y + 5, 34, 22}
	btn_d_plus  = rl.Rectangle{content.x + 390, content.y + 5, 22, 22}
	btn_d_minus = rl.Rectangle{content.x + 414, content.y + 5, 22, 22}
	return
}

// Background color control: full button rect, swatch rect (click to open picker), and popover rect when open.
BG_SWATCH_W   :: f32(24)
BG_SWATCH_H   :: f32(18)
BG_BTN_W      :: f32(80)
BG_POPOVER_W  :: f32(160)
BG_POPOVER_H  :: f32(72)

edit_view_background_rects :: proc(content: rl.Rectangle) -> (btn_rect, swatch_rect, popover_rect: rl.Rectangle) {
	btn_rect    = rl.Rectangle{content.x + content.width - 178 - 8 - BG_BTN_W, content.y + 5, BG_BTN_W, 22}
	swatch_rect = rl.Rectangle{btn_rect.x + BG_BTN_W - BG_SWATCH_W - 4, btn_rect.y + 2, BG_SWATCH_W, BG_SWATCH_H}
	popover_rect = rl.Rectangle{btn_rect.x - 20, content.y + 32 + 2, BG_POPOVER_W, BG_POPOVER_H}
	return
}

// Add Object dropdown layout (shared by draw and update).
ADD_DROPDOWN_W    :: f32(92)
ADD_DROPDOWN_H    :: f32(52)
ADD_DROPDOWN_GAP  :: f32(2)
ADD_ITEM_H        :: f32(24)
ADD_ITEM_GAP      :: f32(2)

// edit_view_add_dropdown_rects returns the dropdown panel and Sphere/Quad item rects given the Add button rect.
edit_view_add_dropdown_rects :: proc(btn_add: rl.Rectangle) -> (dd_rect, sphere_item, quad_item: rl.Rectangle) {
	dd_rect     = rl.Rectangle{btn_add.x, btn_add.y + btn_add.height + ADD_DROPDOWN_GAP, ADD_DROPDOWN_W, ADD_DROPDOWN_H}
	sphere_item = rl.Rectangle{dd_rect.x, dd_rect.y, dd_rect.width, ADD_ITEM_H}
	quad_item   = rl.Rectangle{dd_rect.x, dd_rect.y + ADD_ITEM_H + ADD_ITEM_GAP, dd_rect.width, ADD_ITEM_H}
	return
}
