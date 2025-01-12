package main

import rl "vendor:raylib"
import "core:math"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:strings"

// ---------------------------- Vector 2 stuff ----------------------------

v2 :: rl.Vector2

format_v2 :: proc(v : v2) -> string {
    return fmt.aprint("[%f, %f]", v.x, v.y)
}

tile_size :: 64;
fps :: 60
width: i32 = 800;
height: i32 = 600;

// ---------------------------- Screen Initialization ----------------------------

// initializes the display with some default values
init_display :: proc(fullscreen : bool) {
    rl.InitWindow(width, height, "RTS?")
    rl.SetTargetFPS(fps)
    if !fullscreen {
        return
    }

    monitor := rl.GetCurrentMonitor()
    width = rl.GetMonitorWidth(monitor)
    height = rl.GetMonitorHeight(monitor)
    rl.SetWindowSize(width, height)
    rl.SetWindowPosition(0,0)
    rl.ToggleFullscreen()
}


// ---------------------------- Camera and space transforms ----------------------------

Camera :: struct {
    pos : v2,
    zoom : f32,
}

screen_pos_to_world_pos :: proc(pos : v2) -> v2 {
    screen_center := v2{f32(width/2), f32(height/2)}
    lc := state.camera.pos - (screen_center / state.camera.zoom)
    return lc + (pos / state.camera.zoom)
}

world_pos_to_screen_pos :: proc(pos: v2) -> v2 {
    screen_center := v2{f32(width/2), f32(height/2)}
    diff := pos - state.camera.pos
    return screen_center + (diff * state.camera.zoom)
}

snap_to_grid :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size))*f32(grid_size), math.floor(pos.y / f32(grid_size))*f32(grid_size)}
}

// ---------------------------- Game state ----------------------------

GameState :: struct {
    camera : Camera,

    towers : [dynamic]Tower,
    tower_texture : rl.Texture2D,

    enemies : [dynamic]Enemy,
    enemy_texture : rl.Texture2D,
}

state := GameState {
    camera = Camera {
        pos = v2{0,0},
        zoom = 1.0,
    },
    towers = [dynamic]Tower{},
}

init_assets :: proc() {
    state.tower_texture = rl.LoadTexture("./tower.png")
    state.enemy_texture = rl.LoadTexture("./enemy.png")
}

// ---------------------------- Input handling ----------------------------

handle_keys :: proc() {
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        tower := DefaultTower()
        mouse_pos := rl.GetMousePosition()
        world_space_pos := screen_pos_to_world_pos(mouse_pos)
        tower.pos = snap_to_grid(world_space_pos, tile_size)
        place_tower(tower)
    }

    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        enemy := DefaultEnemy
        mouse_pos := rl.GetMousePosition()
        world_space_pos := screen_pos_to_world_pos(mouse_pos)
        diff := enemy.hitbox/2
        enemy.pos = world_space_pos - diff
        enemy.target = closest_tower(enemy.pos + diff)
        place_enemy(enemy)
    }

    {
        screen_center := v2{f32(width/2), f32(height/2)}
        wm := rl.GetMouseWheelMove()
        zoom_speed : f32 = 0.1
        min_zoom : f32 = 0.1
        if wm != 0 {
            if state.camera.zoom+wm*zoom_speed > min_zoom {
                state.camera.zoom += wm * zoom_speed
            }
        }
    }

    {
        diff := v2{0,0}
        if rl.IsKeyDown(rl.KeyboardKey.W) {
            diff.y -= 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.S) {
            diff.y += 1

        }
        if rl.IsKeyDown(rl.KeyboardKey.A) {
            diff.x -= 1
        }
        if rl.IsKeyDown(rl.KeyboardKey.D) {
            diff.x += 1
        }

        state.camera.pos += rl.Vector2Normalize(diff) * 5
    }
}

// ---------------------------- Game update ----------------------------

update :: proc() {
    for &enemy in state.enemies {
        update_enemy(&enemy)
    }
}

// ---------------------------- Rendering ----------------------------

highlight_tile :: proc(pos : v2) {
    world_pos := screen_pos_to_world_pos(pos)
    world_pos_snapped := snap_to_grid(world_pos, tile_size)
    rl.DrawRectangleV(world_pos_to_screen_pos(world_pos_snapped), v2{tile_size,tile_size} * state.camera.zoom, rl.Color{220,220,220,255})
}

draw :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    highlight_tile(rl.GetMousePosition())

    for tower in state.towers {
        draw_tower(tower)
    }

    for enemy in state.enemies {
        draw_enemy(enemy)
    }

    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("FPS: %d", rl.GetFPS())), 50, 30, 18, rl.BLACK)

    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("camera pos: [%f, %f]", state.camera.pos.x, state.camera.pos.y)), 50, 50, 18, rl.BLACK)
    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("camera dist: [%f]", state.camera.zoom)), 50, 70, 18, rl.BLACK)

    {
        mouse_pos := rl.GetMousePosition()
        mouse_world_pos := screen_pos_to_world_pos(mouse_pos)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse screen pos: [%f, %f]", mouse_pos.x, mouse_pos.y)), 50, 90, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse world pos: [%f, %f]", mouse_world_pos.x, mouse_world_pos.y)), 50, 110, 18, rl.BLACK)
    }

    rl.DrawLine(width/2, 0, width/2, height, rl.BLACK)
    rl.DrawLine(0, height/2, width, height/2, rl.BLACK)

    rl.EndDrawing()
}

// ---------------------------- Main loop ----------------------------

main :: proc() {
    init_display(true)
    init_assets()

    en := DefaultEnemy

    place_enemy(en)

    log(LOG_LEVEL.INFO, "display initialized")

    for !rl.WindowShouldClose() {
        handle_keys()
        update()
        draw()
    }
}
