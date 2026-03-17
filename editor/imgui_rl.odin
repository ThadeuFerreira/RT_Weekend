package editor

// imgui_rl.odin — Raylib → Dear ImGui platform/renderer bridge.
//
// Provides four lifecycle procedures that integrate the Dear ImGui
// docking build with a Raylib OpenGL window.  The caller is responsible
// for the correct ordering:
//
//   imgui_rl_setup()            — after rl.InitWindow()
//   defer imgui_rl_shutdown()
//
//   // inside the frame loop, between BeginDrawing and EndDrawing:
//   imgui_rl_new_frame()        — feeds input + calls imgui.NewFrame()
//   ... imgui draw calls ...
//   imgui_rl_render()           — calls imgui.Render() + GL draw-data submit
//
// There is no dedicated platform backend for Raylib; this file is a
// hand-written equivalent of the rlImGui C library.  It uses
// imgui_impl_opengl3 for GPU rendering and feeds Raylib mouse/keyboard
// state into ImGui's event queue each frame.

import "core:c"
import rl "vendor:raylib"
import imgui "RT_Weekend:vendor/odin-imgui"
import imgui_impl_opengl3 "RT_Weekend:vendor/odin-imgui/imgui_impl_opengl3"

// imgui_rl_setup creates the ImGui context, enables docking and keyboard
// navigation, and initialises the OpenGL 3 rendering backend.
// Call once, immediately after rl.InitWindow() (GL context must be live).
imgui_rl_setup :: proc() {
    imgui.CHECKVERSION()
    imgui.CreateContext(nil)

    io := imgui.GetIO()
    io.ConfigFlags |= {.DockingEnable}
    io.ConfigFlags |= {.NavEnableKeyboard}
    // Persist ImGui window layout between sessions.
    io.IniFilename = "imgui.ini"

    imgui.StyleColorsDark(nil)
    imgui_impl_opengl3.Init("#version 330")
}

// imgui_rl_shutdown tears down the rendering backend and destroys the
// ImGui context.  Call once, after the main loop.
imgui_rl_shutdown :: proc() {
    imgui_impl_opengl3.Shutdown()
    imgui.DestroyContext(nil)
}

// imgui_rl_new_frame feeds the current Raylib window/input state into
// ImGui's IO, then calls imgui.NewFrame().  Call at the start of the
// ImGui section inside BeginDrawing/EndDrawing.
imgui_rl_new_frame :: proc() {
    io := imgui.GetIO()

    // --- display size & timing ---
    io.DisplaySize = imgui.Vec2{
        f32(rl.GetScreenWidth()),
        f32(rl.GetScreenHeight()),
    }
    io.DeltaTime = max(rl.GetFrameTime(), 0.000001)

    // --- mouse position ---
    mp := rl.GetMousePosition()
    imgui.IO_AddMousePosEvent(io, mp.x, mp.y)

    // --- mouse buttons (0=left, 1=right, 2=middle) ---
    imgui.IO_AddMouseButtonEvent(io, 0, rl.IsMouseButtonDown(.LEFT))
    imgui.IO_AddMouseButtonEvent(io, 1, rl.IsMouseButtonDown(.RIGHT))
    imgui.IO_AddMouseButtonEvent(io, 2, rl.IsMouseButtonDown(.MIDDLE))

    // --- mouse wheel ---
    wheel_y := rl.GetMouseWheelMove()
    if wheel_y != 0 {
        imgui.IO_AddMouseWheelEvent(io, 0, wheel_y)
    }

    // --- modifier keys (must come before other keys so ImGui
    //     can set the Ctrl/Shift/Alt flags before processing shortcuts) ---
    _rl_imgui_key(io, .LEFT_CONTROL,  .LeftCtrl)
    _rl_imgui_key(io, .RIGHT_CONTROL, .RightCtrl)
    _rl_imgui_key(io, .LEFT_SHIFT,    .LeftShift)
    _rl_imgui_key(io, .RIGHT_SHIFT,   .RightShift)
    _rl_imgui_key(io, .LEFT_ALT,      .LeftAlt)
    _rl_imgui_key(io, .RIGHT_ALT,     .RightAlt)
    _rl_imgui_key(io, .LEFT_SUPER,    .LeftSuper)
    _rl_imgui_key(io, .RIGHT_SUPER,   .RightSuper)

    // --- navigation / editing keys ---
    _rl_imgui_key(io, .TAB,       .Tab)
    _rl_imgui_key(io, .LEFT,      .LeftArrow)
    _rl_imgui_key(io, .RIGHT,     .RightArrow)
    _rl_imgui_key(io, .UP,        .UpArrow)
    _rl_imgui_key(io, .DOWN,      .DownArrow)
    _rl_imgui_key(io, .PAGE_UP,   .PageUp)
    _rl_imgui_key(io, .PAGE_DOWN, .PageDown)
    _rl_imgui_key(io, .HOME,      .Home)
    _rl_imgui_key(io, .END,       .End)
    _rl_imgui_key(io, .INSERT,    .Insert)
    _rl_imgui_key(io, .DELETE,    .Delete)
    _rl_imgui_key(io, .BACKSPACE, .Backspace)
    _rl_imgui_key(io, .SPACE,     .Space)
    _rl_imgui_key(io, .ENTER,     .Enter)
    _rl_imgui_key(io, .ESCAPE,    .Escape)

    // --- function keys ---
    _rl_imgui_key(io, .F1,  .F1)
    _rl_imgui_key(io, .F2,  .F2)
    _rl_imgui_key(io, .F3,  .F3)
    _rl_imgui_key(io, .F4,  .F4)
    _rl_imgui_key(io, .F5,  .F5)
    _rl_imgui_key(io, .F6,  .F6)
    _rl_imgui_key(io, .F7,  .F7)
    _rl_imgui_key(io, .F8,  .F8)
    _rl_imgui_key(io, .F9,  .F9)
    _rl_imgui_key(io, .F10, .F10)
    _rl_imgui_key(io, .F11, .F11)
    _rl_imgui_key(io, .F12, .F12)

    // --- alphanumeric keys ---
    _rl_imgui_key(io, .A, .A) ; _rl_imgui_key(io, .B, .B)
    _rl_imgui_key(io, .C, .C) ; _rl_imgui_key(io, .D, .D)
    _rl_imgui_key(io, .E, .E) ; _rl_imgui_key(io, .F, .F)
    _rl_imgui_key(io, .G, .G) ; _rl_imgui_key(io, .H, .H)
    _rl_imgui_key(io, .I, .I) ; _rl_imgui_key(io, .J, .J)
    _rl_imgui_key(io, .K, .K) ; _rl_imgui_key(io, .L, .L)
    _rl_imgui_key(io, .M, .M) ; _rl_imgui_key(io, .N, .N)
    _rl_imgui_key(io, .O, .O) ; _rl_imgui_key(io, .P, .P)
    _rl_imgui_key(io, .Q, .Q) ; _rl_imgui_key(io, .R, .R)
    _rl_imgui_key(io, .S, .S) ; _rl_imgui_key(io, .T, .T)
    _rl_imgui_key(io, .U, .U) ; _rl_imgui_key(io, .V, .V)
    _rl_imgui_key(io, .W, .W) ; _rl_imgui_key(io, .X, .X)
    _rl_imgui_key(io, .Y, .Y) ; _rl_imgui_key(io, .Z, .Z)

    _rl_imgui_key(io, .ZERO,  ._0) ; _rl_imgui_key(io, .ONE,   ._1)
    _rl_imgui_key(io, .TWO,   ._2) ; _rl_imgui_key(io, .THREE, ._3)
    _rl_imgui_key(io, .FOUR,  ._4) ; _rl_imgui_key(io, .FIVE,  ._5)
    _rl_imgui_key(io, .SIX,   ._6) ; _rl_imgui_key(io, .SEVEN, ._7)
    _rl_imgui_key(io, .EIGHT, ._8) ; _rl_imgui_key(io, .NINE,  ._9)

    // --- punctuation / symbol keys ---
    _rl_imgui_key(io, .APOSTROPHE,    .Apostrophe)
    _rl_imgui_key(io, .COMMA,         .Comma)
    _rl_imgui_key(io, .MINUS,         .Minus)
    _rl_imgui_key(io, .PERIOD,        .Period)
    _rl_imgui_key(io, .SLASH,         .Slash)
    _rl_imgui_key(io, .SEMICOLON,     .Semicolon)
    _rl_imgui_key(io, .EQUAL,         .Equal)
    _rl_imgui_key(io, .LEFT_BRACKET,  .LeftBracket)
    _rl_imgui_key(io, .BACKSLASH,     .Backslash)
    _rl_imgui_key(io, .RIGHT_BRACKET, .RightBracket)
    _rl_imgui_key(io, .GRAVE,         .GraveAccent)

    // --- lock keys ---
    _rl_imgui_key(io, .CAPS_LOCK,   .CapsLock)
    _rl_imgui_key(io, .SCROLL_LOCK, .ScrollLock)
    _rl_imgui_key(io, .NUM_LOCK,    .NumLock)
    _rl_imgui_key(io, .PRINT_SCREEN, .PrintScreen)
    _rl_imgui_key(io, .PAUSE,        .Pause)

    // --- keypad ---
    _rl_imgui_key(io, .KP_0,        .Keypad0)
    _rl_imgui_key(io, .KP_1,        .Keypad1)
    _rl_imgui_key(io, .KP_2,        .Keypad2)
    _rl_imgui_key(io, .KP_3,        .Keypad3)
    _rl_imgui_key(io, .KP_4,        .Keypad4)
    _rl_imgui_key(io, .KP_5,        .Keypad5)
    _rl_imgui_key(io, .KP_6,        .Keypad6)
    _rl_imgui_key(io, .KP_7,        .Keypad7)
    _rl_imgui_key(io, .KP_8,        .Keypad8)
    _rl_imgui_key(io, .KP_9,        .Keypad9)
    _rl_imgui_key(io, .KP_DECIMAL,  .KeypadDecimal)
    _rl_imgui_key(io, .KP_DIVIDE,   .KeypadDivide)
    _rl_imgui_key(io, .KP_MULTIPLY, .KeypadMultiply)
    _rl_imgui_key(io, .KP_SUBTRACT, .KeypadSubtract)
    _rl_imgui_key(io, .KP_ADD,      .KeypadAdd)
    _rl_imgui_key(io, .KP_ENTER,    .KeypadEnter)

    // --- text / unicode characters typed this frame ---
    for {
        ch := rl.GetCharPressed()
        if ch == 0 { break }
        imgui.IO_AddInputCharacter(io, c.uint(ch))
    }

    // Let the OpenGL3 backend update its internal state, then start the frame.
    imgui_impl_opengl3.NewFrame()
    imgui.NewFrame()
}

// imgui_rl_render finalises the ImGui frame and submits the draw data
// to the OpenGL3 backend.  Call just before rl.EndDrawing().
imgui_rl_render :: proc() {
    imgui.Render()
    imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
}

// imgui_rl_want_capture_mouse returns true when ImGui wants exclusive
// ownership of mouse input (hovering a window, widget active, etc.).
// Use to skip Raylib mouse processing when ImGui is consuming it.
imgui_rl_want_capture_mouse :: proc() -> bool {
    return imgui.GetIO().WantCaptureMouse
}

// imgui_rl_want_capture_keyboard returns true when ImGui wants exclusive
// ownership of keyboard input (e.g. text widget focused).
imgui_rl_want_capture_keyboard :: proc() -> bool {
    return imgui.GetIO().WantCaptureKeyboard
}

// _rl_imgui_key is an internal helper that reports a single Raylib key's
// current down state to ImGui's event queue.
@(private)
_rl_imgui_key :: proc(io: ^imgui.IO, rl_key: rl.KeyboardKey, imgui_key: imgui.Key) {
    imgui.IO_AddKeyEvent(io, imgui_key, rl.IsKeyDown(rl_key))
}
