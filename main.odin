package main

import "core:slice"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/rand"
import "core:math/noise"
import rl "vendor:raylib"


world_size :: 128
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
    rl.DrawTextureEx(state.atlas.wall_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
}

// takes a position in world space not snapped
place_wall :: proc(p : v2) {
    wall := DefaultWall
    wall.pos = snap_to_grid(p, tile_size)

    wall_grid_pos := grid_position(wall.pos, tile_size)
    target_tile := state.world[i32(wall_grid_pos.y)][i32(wall_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.buildings, wall)
    }
}

Building :: union {
    Tower,
    Wall,
}

building_types :: 2

building_string :: proc(b : Building) -> string {
    switch b in b {
    case Tower: return "Tower"
    case Wall: return "Wall"
    }
    return "ligma"
}

place_building :: proc(b : Building, p : v2) {
    switch b in b {
    case Tower: place_tower(p)
    case Wall: place_wall(p)
    }
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
    grass_texture_0 : rl.Texture2D,
    grass_texture_1 : rl.Texture2D,
    grass_texture_2 : rl.Texture2D,
    grass_texture_3 : rl.Texture2D,
    water_texture : rl.Texture2D,
    forest_texture : rl.Texture2D,
    rock_texture : rl.Texture2D,
    wall_texture : rl.Texture2D,
    orc_texture : rl.Texture2D,
    berserk_texture : rl.Texture2D,
}

init_texture_atlas :: proc() {
    atlas : TextureAtlas
    atlas.tower_texture = rl.LoadTexture("./tower.png")
    atlas.enemy_texture = rl.LoadTexture("./enemy.png")
    atlas.grass_texture_0 = rl.LoadTexture("./grass_0.png")
    atlas.grass_texture_1 = rl.LoadTexture("./grass_1.png")
    atlas.grass_texture_2 = rl.LoadTexture("./grass_2.png")
    atlas.grass_texture_3 = rl.LoadTexture("./grass_3.png")
    atlas.water_texture = rl.LoadTexture("./water.png")
    atlas.forest_texture = rl.LoadTexture("./forest.png")
    atlas.rock_texture = rl.LoadTexture("./rock.png")
    atlas.wall_texture = rl.LoadTexture("./wall.png")
    atlas.orc_texture = rl.LoadTexture("./orc.png")
    atlas.berserk_texture = rl.LoadTexture("./berserk.png")
    state.atlas = atlas
}

deinit_texture_atlas :: proc() {
    rl.UnloadTexture(state.atlas.tower_texture)
    rl.UnloadTexture(state.atlas.enemy_texture)
    rl.UnloadTexture(state.atlas.grass_texture_0)
    rl.UnloadTexture(state.atlas.grass_texture_1)
    rl.UnloadTexture(state.atlas.grass_texture_2)
    rl.UnloadTexture(state.atlas.grass_texture_3)
    rl.UnloadTexture(state.atlas.water_texture)
    rl.UnloadTexture(state.atlas.forest_texture)
    rl.UnloadTexture(state.atlas.rock_texture)
    rl.UnloadTexture(state.atlas.wall_texture)
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
    .Rock = false,
}

Tile :: struct {
    pos : v2,
    kind : TileKind,
    texture : ^rl.Texture2D,
    shade: f32
}

draw_tile :: proc(t : Tile) {
    a := u8(255.0 * t.shade)
    rl.DrawTextureEx(t.texture^, world_pos_to_screen_pos(t.pos), 0.0, state.camera.zoom, rl.Color{a, a, a, 255})
}

Orc :: struct {
    pos : v2,
    spd : f32,
    target : v2,
    health : i32,
    max_health : i32,
    damage : i32,
}

DefaultOrc :: Orc {
    pos = v2{0,0},
    spd = 4.0,
    health = 100,
    max_health = 100,
    damage = 10,
}

place_orc :: proc(pos : v2) {
    orc := DefaultOrc
    orc.pos = pos
    orc.target = orc.pos

    orc_grid_pos := grid_position(orc.pos + v2{f32(tile_size/2), f32(tile_size/2)}, tile_size)
    target_tile := state.world[i32(orc_grid_pos.y)][i32(orc_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.units, orc)
    }
}

draw_orc :: proc(orc : Orc) {
    pos := world_pos_to_screen_pos(orc.pos)
    rl.DrawTextureEx(state.atlas.orc_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
}

Berserk :: struct {
    pos : v2,
    spd : f32,
    health : i32,
    target : v2,
    max_health : i32,
    damage : i32,
}

DefaultBerserk :: Berserk {
    pos = v2{0,0},
    spd = 8.0,
    health = 50,
    max_health = 50,
    damage = 20,
}

place_berserk :: proc(pos : v2) {
    berserk := DefaultBerserk
    berserk.pos = pos
    berserk.target = berserk.pos

    berserk_grid_pos := grid_position(berserk.pos + v2{f32(tile_size/2), f32(tile_size/2)}, tile_size)
    target_tile := state.world[i32(berserk_grid_pos.y)][i32(berserk_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.units, berserk)
    }
}

draw_berserk :: proc(berserk : Berserk) {
    pos := world_pos_to_screen_pos(berserk.pos)
    rl.DrawTextureEx(state.atlas.berserk_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
}

Unit :: union {
    Orc,
    Berserk,
}

unit_pos :: proc(u : Unit) -> v2 {
    switch u in u {
    case Orc: return u.pos
    case Berserk: return u.pos
    }
    return v2{0,0}
}

unit_set_target :: proc(u : ^Unit, tgt : v2) {
    switch &u in u {
    case Orc: u.target = tgt
    case Berserk: u.target = tgt
    }
}

update_unit :: proc(u : ^Unit) {
    switch &u in u {
    case Orc: {
        if u.pos != u.target {
            diff := u.target - u.pos
            if rl.Vector2Length(diff) < u.spd {
                u.pos = u.target
            } else {
                u.pos += rl.Vector2Normalize(diff)*u.spd
            }
        }
    }
    case Berserk: {
        if u.pos != u.target {
            diff := u.target - u.pos
            if rl.Vector2Length(diff) < u.spd {
                u.pos = u.target
            } else {
                u.pos += rl.Vector2Normalize(diff)*u.spd
            }
        }
    }
    }
}

unit_string :: proc(u : Unit) -> string {
    switch u in u {
    case Orc: return "Orc"
    case Berserk: return "Berserk"
    }
    return "ligma"
}

place_unit :: proc(u : Unit, pos : v2) {
    switch u in u {
    case Orc: place_orc(pos)
    case Berserk: place_berserk(pos)
    }
}

draw_unit :: proc(u : Unit) {
    switch u in u {
    case Orc: draw_orc(u)
    case Berserk: draw_berserk(u)
    }
}

InteractState :: enum {
    None,
    Building,
    Spawning,
}

GameState :: struct {
    alloc : mem.Allocator,
    camera : Camera,

    atlas : TextureAtlas,

    buildings : [dynamic]Building,
    world : ^[world_size][world_size]Tile,

    selected_building : Building,

    interact_state : InteractState,

    units : [dynamic]Unit,
    selected_unit : Unit,

    debug : bool,

    dragging : bool,
    drag_start : v2,
    drag_end : v2,

    selected_units : []^Unit
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

    state.selected_building = Tower{}
    state.selected_unit = Orc{}

    state.interact_state = .None

    state.debug = false

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
            kind := noise_to_tile(noise[(y*world_size) + x])

            tile := Tile{
                kind = kind,
                shade = 1.0,
                pos = v2{f32(x), f32(y)} * f32(tile_size)
            }

            switch kind {
            case.Grass: {
                grass_textures_choice := []^rl.Texture2D{&state.atlas.grass_texture_0, &state.atlas.grass_texture_1, &state.atlas.grass_texture_2, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3, &state.atlas.grass_texture_3}
                tile.texture = rand.choice(grass_textures_choice)
                tile.shade = 0.98+(rand.float32()*0.02)
            }
            case.Rock: {
                tile.texture = &state.atlas.rock_texture
                tile.shade = (1.0 - noise[(y*world_size) + x])/0.25
            }
            case.Water: {
                tile.texture = &state.atlas.water_texture
                tile.shade = (1.0 - (0.1 - noise[(y*world_size)+x]))
            }
            case.Forest: {
                tile.texture = &state.atlas.forest_texture
            }
            }

            state.world[y][x] = tile
        }
    }

    state.alloc = alloc
}

map_mut :: proc(xs: []$T, fn: proc(^T) -> $R) -> []R {
    result := make([]R, len(xs))
    for &x, i in xs {
        result[i] = fn(&x)
    }
    return result
}

deinit_game_state :: proc() {
    mem.free_all(state.alloc)
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
    // dragging behavior
    if state.interact_state == .None {
        if rl.IsKeyPressed(rl.KeyboardKey.M) || rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
            for &u in state.selected_units {
                unit_set_target(u, screen_pos_to_world_pos(rl.GetMousePosition() - v2{f32(tile_size/2), f32(tile_size/2)}))
            }
        }

        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            state.selected_units = []^Unit{}
            state.dragging = true
            state.drag_start = screen_pos_to_world_pos(rl.GetMousePosition())
            state.drag_end = state.drag_start
        }

        state.drag_end = screen_pos_to_world_pos(rl.GetMousePosition())

        if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
            state.dragging = false

            unit_ptrs := map_mut(state.units[:], proc (u : ^Unit) -> ^Unit {
                return u
            })

            units, _ := slice.filter(unit_ptrs, proc (u : ^Unit) -> bool {
                pos := unit_pos(u^)
                return (pos.x >= state.drag_start.x && pos.x <= state.drag_end.x &&
                        pos.y >= state.drag_start.y && pos.y <= state.drag_end.y)
            })

            state.selected_units = units
            for u in units {
                rl.DrawCircleV(world_pos_to_screen_pos(unit_pos(u^)), f32(tile_size/2), rl.Color{0,255,0, 50})
            }
        }
    }
    // reset buildings and enemies
    {
        if rl.IsKeyPressed(rl.KeyboardKey.R) {
            clear(&state.buildings)
            clear(&state.units)
        }
    }
    // interact state toggling
    {
        if rl.IsKeyPressed(rl.KeyboardKey.B) {
            if state.interact_state != .Building {
                state.interact_state = .Building
            } else {
                state.interact_state = .None
            }
        }
        if rl.IsKeyPressed(rl.KeyboardKey.G) {
            if state.interact_state != .Spawning {
                state.interact_state = .Spawning
            } else {
                state.interact_state = .None
            }
        }
    }
    // debug toggling
    {
        if rl.IsKeyPressed(rl.KeyboardKey.GRAVE) {
            state.debug = !state.debug
        }
    }
    // camera zoom
    {
        wm := rl.GetMouseWheelMove()
        zoom_speed : f32 = 0.1
        min_zoom : f32 = 0.1
        if wm != 0 {
            if state.camera.zoom+wm*zoom_speed > min_zoom {
                state.camera.zoom += wm * zoom_speed
            } else {
                state.camera.zoom = min_zoom
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

        state.camera.pos += rl.Vector2Normalize(diff) * 1000 / state.camera.zoom * rl.GetFrameTime()
    }
    // placing buildings
    {
        if state.interact_state == .Building {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                place_building(state.selected_building, screen_pos_to_world_pos(rl.GetMousePosition()))
            }

            // changing selected building
            if rl.IsKeyPressed(rl.KeyboardKey.ONE) {
                state.selected_building = Tower{}
            } else if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
                state.selected_building = Wall{}
            }
        }
    }
    // spawning units
    {
        if state.interact_state == .Spawning {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                place_unit(state.selected_unit, screen_pos_to_world_pos(rl.GetMousePosition()) - v2{f32(tile_size/2), f32(tile_size/2)})
            }

            // changing selected unit
            if rl.IsKeyPressed(rl.KeyboardKey.ONE) {
                state.selected_unit = Orc{}
            } else if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
                state.selected_unit = Berserk{}
            }
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
    for &u in state.units {
        update_unit(&u)
    }
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

draw_gui :: proc() {
    bottom_anchor := i32(state.camera.screen_size.y)
    bottom_anchor_f := state.camera.screen_size.y
    // building ui
    {
        rl.DrawText("TOGGLE BUILDING MODE WITH <B>", 50, bottom_anchor - 30, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", building_string(state.selected_building))), 50, bottom_anchor - 50, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECT BUILDING <1 ... %d>", building_types)), 50, bottom_anchor - 70, 18, rl.BLACK)

        accent := rl.WHITE
        if state.interact_state != .Building {
            accent = rl.RED
        }
        texture : rl.Texture2D
        switch b in state.selected_building {
        case Tower: texture = state.atlas.tower_texture
        case Wall: texture = state.atlas.wall_texture
        }
        rl.DrawTextureV(texture, v2{50, bottom_anchor_f - 80 - f32(tile_size)}, accent)
    }
    // spawning ui
    {
        spawning_bottom_anchor := bottom_anchor - 80 - tile_size
        spawning_bottom_anchor_f := f32(bottom_anchor - 80 - tile_size)
        rl.DrawText("TOGGLE SPAWNING MODE WITH <G>", 50, spawning_bottom_anchor - 30, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", unit_string(state.selected_unit))), 50, spawning_bottom_anchor - 50, 18, rl.BLACK)
        accent := rl.WHITE
        if state.interact_state != .Spawning {
            accent = rl.RED
        }
        texture : rl.Texture2D
        switch u in state.selected_unit {
        case Orc: texture = state.atlas.orc_texture
        case Berserk: texture = state.atlas.berserk_texture
        }
        rl.DrawTextureV(texture, v2{50, spawning_bottom_anchor_f - 50 - f32(tile_size) - 10}, accent)
    }
    // dragging ui
    if state.dragging {
        pos := world_pos_to_screen_pos(state.drag_start)
        rl.DrawRectangleV(pos, world_pos_to_screen_pos(state.drag_end) - pos, rl.Color{120,120,120,50})
    }
    // selected unit gui
    for u in state.selected_units {
        rl.DrawRectangleV(world_pos_to_screen_pos(unit_pos(u^)), v2{f32(tile_size), f32(tile_size)}*state.camera.zoom, rl.Color{0,255,0,50})
    }
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

    for u in state.units {
        draw_unit(u)
    }

    if state.interact_state == .Building {
        highlight_tile(rl.GetMousePosition())
    }
    draw_gui()
    if state.debug {
        draw_debug_info()
    }

    rl.EndDrawing()
}

main :: proc() {
    init_display(false)
    log(LOG_LEVEL.INFO, "display initialized")

    init_game_state()
    log(LOG_LEVEL.INFO, "game state initialized")
    defer deinit_game_state()

    init_texture_atlas()
    log(LOG_LEVEL.INFO, "texture atlas initialized")
    defer deinit_texture_atlas()

    for !rl.WindowShouldClose() {
        update()
        draw()
    }
}
