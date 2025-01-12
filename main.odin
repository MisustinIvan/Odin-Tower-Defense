package main

import "core:slice"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/rand"
import "core:math/noise"
import rl "vendor:raylib"


world_size :: 256
tile_size :: 64;
fps :: 60
default_width :: 800
default_height :: 600

v2 :: rl.Vector2

Camera :: struct {
    fps : i32,
    pos : v2,
    zoom : f32,
    screen_size : v2,
}

screen_pos_to_world_pos :: proc(pos : v2) -> v2 {
    screen_center := state.camera.screen_size/2
    lc := state.camera.pos - (screen_center / state.camera.zoom)
    return lc + (pos / state.camera.zoom)
}

world_pos_to_screen_pos :: proc(pos: v2) -> v2 {
    screen_center := state.camera.screen_size/2
    diff := pos - state.camera.pos
    return screen_center + (diff * state.camera.zoom)
}

snap_to_grid :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size))*f32(grid_size), math.floor(pos.y / f32(grid_size))*f32(grid_size)}
}

grid_position :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size)), math.floor(pos.y / f32(grid_size))}
}

Tower :: struct {
    pos : v2,
    hitbox : v2,
    health : i32,
    max_health : i32,
}

DefaultTower :: Tower {
    pos = v2{0,0},
    hitbox = v2{f32(tile_size),f32(tile_size)},
    health = 100,
    max_health = 100,
}

draw_tower :: proc(t : Tower) {
    pos := world_pos_to_screen_pos(t.pos)
    if t.health <= 0 {
        rl.DrawTextureEx(state.atlas.tower_texture, pos, 0.0, state.camera.zoom, rl.RED)
    } else {
        rl.DrawTextureEx(state.atlas.tower_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
    }
}

// takes a position in world space not snapped
place_tower :: proc(p : v2) {
    tower := DefaultTower
    tower.pos = snap_to_grid(p, tile_size)

    tower_grid_pos := grid_position(tower.pos, tile_size)
    target_tile := state.world[i32(tower_grid_pos.y)][i32(tower_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.buildings, tower)
    }
}

Wall :: struct {
    pos : v2,
    hitbox : v2,
    health : v2,
    max_health : i32,
}

DefaultWall :: Wall {
    pos = v2{0,0},
    hitbox = v2{f32(tile_size),f32(tile_size)},
    health = 100,
    max_health = 100,
}

draw_wall :: proc(t : Wall) {
    pos := world_pos_to_screen_pos(t.pos)
    col := rl.Color{255,0,255,255}
    rl.DrawRectangleV(pos, t.hitbox*state.camera.zoom, col)
}

// takes a position in world space not snapped
place_wall :: proc(p : v2) {
    wall := DefaultWall
    wall.pos = snap_to_grid(p, tile_size)
    append(&state.buildings, wall)
}

Building :: union {
    Tower,
    Wall,
}

draw_building :: proc(b : Building) {
    switch b in b {
    case Tower: draw_tower(b)
    case Wall: draw_wall(b)
    }
}

TextureAtlas :: struct {
    tower_texture : rl.Texture2D,
    enemy_texture : rl.Texture2D,
    grass_texture : rl.Texture2D,
    water_texture : rl.Texture2D,
    forest_texture : rl.Texture2D,
    rock_texture : rl.Texture2D,
}

init_texture_atlas :: proc() {
    atlas : TextureAtlas
    atlas.tower_texture = rl.LoadTexture("./tower.png")
    atlas.enemy_texture = rl.LoadTexture("./enemy.png")
    atlas.grass_texture = rl.LoadTexture("./grass.png")
    atlas.water_texture = rl.LoadTexture("./water.png")
    atlas.forest_texture = rl.LoadTexture("./forest.png")
    atlas.rock_texture = rl.LoadTexture("./rock.png")
    state.atlas = atlas
}

deinit_texture_atlas :: proc() {
    rl.UnloadTexture(state.atlas.tower_texture)
    rl.UnloadTexture(state.atlas.enemy_texture)
}

TileKind :: enum {
    Grass,
    Water,
    Forest,
    Rock,
}

PlaceableTile :: [TileKind]bool {
    .Grass = true,
    .Water = false,
    .Forest = false,
    .Rock = true,
}

Tile :: struct {
    pos : v2,
    kind : TileKind
}

draw_tile :: proc(t : Tile) {
    texture : rl.Texture2D
    switch t.kind {
    case .Grass: texture = state.atlas.grass_texture
    case .Water: texture = state.atlas.water_texture
    case .Forest: texture = state.atlas.forest_texture
    case .Rock: texture = state.atlas.rock_texture
    }
    rl.DrawTextureEx(texture, world_pos_to_screen_pos(t.pos), 0.0, state.camera.zoom, rl.WHITE)
}

GameState :: struct {
    alloc : mem.Allocator,
    camera : Camera,

    atlas : TextureAtlas,

    buildings : [dynamic]Building,
    world : ^[world_size][world_size]Tile
}

DefaultGameState :: proc() -> GameState {
    return GameState{
        camera = Camera {
            pos = v2{0,0},
            zoom = 1.0,
        }
    }
}

state : GameState

smoothstep :: proc(t : f32) -> f32 {
    return t * t * t * (t * (t * 6 - 15) + 10)
}

lerp :: proc(a : f32, b : f32, t : f32) -> f32 {
    return a + t * (b - a)
}

generate_perlin_noise :: proc(width, height : i32, scale : f32 = 1.0, alloc := context.allocator) -> []f32 {
    result, err := make([]f32, width*height)
    if err != .None {
        log(.PANIC, "failed to allocate memory for noise")
    }

    seed := rand.int63()


    for y in 0..<height {
        for x in 0..<width {
            coord := v2{f32(x),f32(y)}/scale
            result[(y * width) + x] = (noise.noise_2d(seed, noise.Vec2{f64(coord.x), f64(coord.y)}) + 1.0) * 0.5
        }
    }

    return result
}

noise_to_tile :: proc(val : f32) -> TileKind {
    if val <= 0.1 {
        return .Water
    } else if val <= 0.7 {
        return .Grass
    } else if val <= 0.85 {
        return .Forest
    } else {
        return .Rock
    }
}

init_game_state :: proc(alloc := context.allocator) {
    state.camera = Camera {
        pos = v2{0,0},
        zoom = 1.0,
    }

    if state.camera.screen_size.x == 0.0 && state.camera.screen_size.y == 0.0 {
        state.camera.screen_size = v2{f32(default_width), f32(default_height)}
    }


    size := size_of(Tile) * world_size * world_size
    tiles_ptr, err := mem.alloc(size, mem.DEFAULT_ALIGNMENT, alloc)
    if err != mem.Allocator_Error.None {
        log(LOG_LEVEL.PANIC, "Failed to allocate memory for world")
    }

    state.world = cast(^[world_size][world_size]Tile)(tiles_ptr)

    noise := generate_perlin_noise(world_size, world_size, 32)

    for row, y in state.world {
        for _, x in row {
            tile := Tile{
                kind = noise_to_tile(noise[(y*world_size) + x]),
                pos = v2{f32(x), f32(y)} * f32(tile_size)
            }
            state.world[y][x] = tile
        }
    }

    state.alloc = alloc
}

init_display :: proc(fullscreen : bool) {
    rl.InitWindow(default_width, default_height, "RTS?")
    rl.SetTargetFPS(fps)
    if !fullscreen {
        return
    }

    monitor := rl.GetCurrentMonitor()
    width := rl.GetMonitorWidth(monitor)
    height := rl.GetMonitorHeight(monitor)

    state.camera.screen_size.x = f32(width)
    state.camera.screen_size.y = f32(height)
    rl.SetWindowSize(width, height)
    rl.SetWindowPosition(0,0)
    rl.ToggleFullscreen()
}

handle_input :: proc() {
    // camera zoom
    {
        wm := rl.GetMouseWheelMove()
        zoom_speed : f32 = 0.1
        min_zoom : f32 = 0.1
        if wm != 0 {
            if state.camera.zoom+wm*zoom_speed > min_zoom {
                state.camera.zoom += wm * zoom_speed
            }
        }
    }
    // camera movement
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

        state.camera.pos += rl.Vector2Normalize(diff) * 10 / state.camera.zoom
    }
    // placing buildings
    {
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            place_tower(screen_pos_to_world_pos(rl.GetMousePosition()))
        }
        if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
            place_wall(screen_pos_to_world_pos(rl.GetMousePosition()))
        }
    }
    // fullscreen toggle
    {
        if rl.IsKeyPressed(rl.KeyboardKey.F) {
            if rl.IsWindowFullscreen() {
                rl.ToggleFullscreen()
                rl.SetWindowSize(default_width, default_height)
                state.camera.screen_size.x = f32(default_width)
                state.camera.screen_size.y = f32(default_height)
                rl.SetWindowPosition(50,50)
            } else {
                monitor := rl.GetCurrentMonitor()
                width := rl.GetMonitorWidth(monitor)
                height := rl.GetMonitorHeight(monitor)

                rl.SetWindowSize(width, height)
                rl.SetWindowPosition(0,0)
                rl.ToggleFullscreen()

                state.camera.screen_size.x = f32(width)
                state.camera.screen_size.y = f32(height)
            }
        }
    }
}

update :: proc() {
    handle_input()
}

highlight_tile :: proc(pos : v2) {
    world_pos := screen_pos_to_world_pos(pos)
    world_pos_snapped := snap_to_grid(world_pos, tile_size)
    rl.DrawRectangleV(world_pos_to_screen_pos(world_pos_snapped), v2{tile_size,tile_size} * state.camera.zoom, rl.Color{220,220,220,120})
}

draw_world_grid :: proc() {
    screen_size := state.camera.screen_size
    top_left := screen_pos_to_world_pos(v2{0, 0})
    bottom_right := screen_pos_to_world_pos(screen_size)

    start_x := math.floor(top_left.x / f32(tile_size))
    start_y := math.floor(top_left.y / f32(tile_size))
    end_x := math.ceil(bottom_right.x / f32(tile_size))
    end_y := math.ceil(bottom_right.y / f32(tile_size))

    col1 := rl.Color{180, 180, 180, 255}
    col2 := rl.Color{200, 200, 200, 255}
    for y in start_y..<end_y {
        for x in start_x..<end_x {
            world_pos := v2{f32(x) * f32(tile_size), f32(y) * f32(tile_size)}

            screen_pos := world_pos_to_screen_pos(world_pos)

            col : rl.Color
            if i32(x + y) % 2 == 0 {
                col = col1
            } else {
                col = col2
            }
            rl.DrawRectangleV(screen_pos, v2{f32(tile_size), f32(tile_size)} * state.camera.zoom, col)
        }
    }
}

draw_debug_info :: proc() {
    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("FPS: %d", rl.GetFPS())), 50, 30, 18, rl.BLACK)

    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("camera pos: [%f, %f]", state.camera.pos.x, state.camera.pos.y)), 50, 50, 18, rl.BLACK)
    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("camera dist: [%f]", state.camera.zoom)), 50, 70, 18, rl.BLACK)

    {
        mouse_pos := rl.GetMousePosition()
        mouse_world_pos := screen_pos_to_world_pos(mouse_pos)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse screen pos: [%f, %f]", mouse_pos.x, mouse_pos.y)), 50, 90, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse world pos: [%f, %f]", mouse_world_pos.x, mouse_world_pos.y)), 50, 110, 18, rl.BLACK)
    }

    rl.DrawLine(i32(state.camera.screen_size.x/2), 0, i32(state.camera.screen_size.x/2), i32(state.camera.screen_size.y), rl.BLACK)
    rl.DrawLine(0, i32(state.camera.screen_size.y/2), i32(state.camera.screen_size.x), i32(state.camera.screen_size.y/2), rl.BLACK)
}

draw :: proc() {
    rl.BeginDrawing()

    rl.ClearBackground(rl.WHITE)

    draw_world_grid()

    for row in state.world {
        for tile in row {
            draw_tile(tile)
        }
    }

    for b in state.buildings {
        draw_building(b)
    }

    highlight_tile(rl.GetMousePosition())
    draw_debug_info()

    rl.EndDrawing()
}

main :: proc() {
    init_display(false)
    log(LOG_LEVEL.INFO, "display initialized")
    init_game_state()
    log(LOG_LEVEL.INFO, "game state initialized")
    init_texture_atlas()
    log(LOG_LEVEL.INFO, "texture atlas initialized")
    defer deinit_texture_atlas()

    for !rl.WindowShouldClose() {
        update()
        draw()
    }
}
