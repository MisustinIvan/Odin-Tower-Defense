package main

import "core:slice"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/rand"
import "core:math/noise"
import rl "vendor:raylib"


world_size :: 512
tile_size :: 64;
tile_size_offset :: v2{f32(tile_size/2), f32(tile_size/2)}
fps :: 60
default_width :: 800
default_height :: 600

v2 :: rl.Vector2
rect :: rl.Rectangle

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

world_pos_to_screen_pos :: proc(pos : v2) -> v2 {
    screen_center := state.camera.screen_size/2
    diff := pos - state.camera.pos
    return screen_center + (diff * state.camera.zoom)
}

cull_pos :: proc(pos : v2) -> bool {
    min := state.camera.pos - (state.camera.screen_size /  state.camera.zoom  / 2)
    max := min + (state.camera.screen_size / state.camera.zoom)
    return pos.x >= min.x && pos.x <= max.x && pos.y >= min.y && pos.y <= max.y
}

cull_rect_full :: proc(pos : v2, size : v2) -> bool {
    min := state.camera.pos - (state.camera.screen_size /  state.camera.zoom  / 2)
    max := min + (state.camera.screen_size / state.camera.zoom)

    p1 := pos
    p2 := p1 + size
    p3 := p1 + v2{size.x, 0}
    p4 := p1 + v2{0, size.y}

    return  (p1.x >= min.x && p1.x <= max.x && p1.y >= min.y && p1.y <= max.y) ||
            (p2.x >= min.x && p2.x <= max.x && p2.y >= min.y && p2.y <= max.y) ||
            (p3.x >= min.x && p3.x <= max.x && p3.y >= min.y && p3.y <= max.y) ||
            (p4.x >= min.x && p4.x <= max.x && p4.y >= min.y && p4.y <= max.y)
}

cull_rect_partial :: proc(pos : v2, size : v2) -> bool {
    min := state.camera.pos - (state.camera.screen_size / state.camera.zoom / 2)
    max := min + (state.camera.screen_size / state.camera.zoom)

    return !(pos.x + size.x < min.x || pos.x > max.x || pos.y + size.y < min.y || pos.y > max.y)
}

cull_camera_bounds :: proc() -> (v2, v2) {
    y_min := min(world_size - 1, max(0, i32(math.floor((state.camera.pos.y - (state.camera.screen_size.y / 2 / state.camera.zoom)) / f32(tile_size)))))
    y_max := min(world_size - 1, y_min + i32(math.ceil(state.camera.screen_size.y / tile_size / state.camera.zoom)) + 1)

    x_min := min(world_size - 1, max(0, i32(math.floor((state.camera.pos.x - (state.camera.screen_size.x / 2 / state.camera.zoom)) / f32(tile_size)))))
    x_max := min(world_size - 1, x_min + i32(math.ceil(state.camera.screen_size.x / tile_size / state.camera.zoom)) + 1)
    return v2{f32(x_min), f32(y_min)}, v2{f32(x_max), f32(y_max)}
}

snap_to_grid :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size))*f32(grid_size), math.floor(pos.y / f32(grid_size))*f32(grid_size)}
}

grid_position :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size)), math.floor(pos.y / f32(grid_size))}
}

BuildingKind :: enum {
    Tower,
    Wall,
}

@(rodata)
BuildingTextureKind := [BuildingKind]TextureKind {
    .Tower = .TowerTexture,
    .Wall = .WallTexture,

}
BuildingKindN :: 2

Building :: struct {
    kind : BuildingKind,
    texture : TextureKind,
    pos : v2,
    health : i32,
    max_health : i32,
}

DefaultTower :: Building {
    kind = .Tower,
    texture = .TowerTexture,
    health = 100,
    max_health = 100,
}

DefaultWall :: Building {
    kind = .Wall,
    texture = .WallTexture,
    health = 100,
    max_health = 100,
}

draw_building :: proc(b : Building) {
    pos := world_pos_to_screen_pos(b.pos)
    texture : rl.Texture2D
    accent : rl.Color

    if b.health <= 0 {
        accent = rl.RED
    } else {
        accent = rl.WHITE
    }

    rl.DrawTextureEx(state.atlas.textures[b.texture], pos, 0.0, state.camera.zoom, accent)
}

// takes a position in world space not snapped
place_building :: proc(k : BuildingKind, p : v2) {
    building : Building

    switch k {
    case .Tower: building = DefaultTower;
    case .Wall: building = DefaultWall;
    }

    building.pos = snap_to_grid(p, tile_size)

    building_grid_pos := grid_position(building.pos, tile_size)
    target_tile := state.world[i32(building_grid_pos.y)][i32(building_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.buildings, building)
    }
}

building_kind_string :: proc(k : BuildingKind) -> string {
    res : string
    switch k {
    case .Tower: res = "Tower"
    case .Wall: res = "Wall"
    }
    return res
}

TextureKind :: enum {
    WaterTexture,
    GrassTexture0,
    GrassTexture1,
    GrassTexture2,
    GrassTexture3,
    ForestTexture,
    RockTexture,
    TowerTexture,
    WallTexture,
    OrcTexture,
    BerserkTexture,
}

TextureAtlas :: struct {
    textures : [TextureKind]rl.Texture2D
}

init_texture_atlas :: proc() {
    state.atlas = TextureAtlas{}
    state.atlas.textures[.WaterTexture] = rl.LoadTexture("./water.png")
    state.atlas.textures[.GrassTexture0] = rl.LoadTexture("./grass_0.png")
    state.atlas.textures[.GrassTexture1] = rl.LoadTexture("./grass_1.png")
    state.atlas.textures[.GrassTexture2] = rl.LoadTexture("./grass_2.png")
    state.atlas.textures[.GrassTexture3] = rl.LoadTexture("./grass_3.png")
    state.atlas.textures[.ForestTexture] = rl.LoadTexture("./forest.png")
    state.atlas.textures[.RockTexture] = rl.LoadTexture("./rock.png")
    state.atlas.textures[.TowerTexture] = rl.LoadTexture("./tower.png")
    state.atlas.textures[.WallTexture] = rl.LoadTexture("./wall.png")
    state.atlas.textures[.OrcTexture] = rl.LoadTexture("./orc.png")
    state.atlas.textures[.BerserkTexture] = rl.LoadTexture("./berserk.png")
}

deinit_texture_atlas :: proc() {
    for texture in state.atlas.textures {
        rl.UnloadTexture(texture)
    }
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
    texture : TextureKind,
    shade: f32
}

tile_rect :: proc(t : Tile) -> rect {
    return rect {x = t.pos.x, y = t.pos.x, width = f32(tile_size), height = f32(tile_size)}
}

draw_tile :: proc(t : Tile) {
    a := u8(255.0 * t.shade)
    rl.DrawTextureEx(state.atlas.textures[t.texture], world_pos_to_screen_pos(t.pos), 0.0, state.camera.zoom, rl.Color{a, a, a, 255})
}

UnitKind :: enum {
    Orc,
    Berserk,
}

@(rodata)
UnitKindTexture := [UnitKind]TextureKind {
    .Orc = .OrcTexture,
    .Berserk = .BerserkTexture,
}

UnitKindN :: 2

unit_kind_string :: proc(k : UnitKind) -> string {
    res : string
    switch k {
    case .Orc: res = "Orc";
    case .Berserk: res = "Berserk"
    }
    return res
}

Unit :: struct {
    kind: UnitKind,
    texture : TextureKind,
    pos : v2,
    health : i32,
    max_health : i32,
    damage : i32,
    target : v2,
    spd : f32,
}

DefaultOrc :: Unit {
    kind = .Orc,
    texture = .OrcTexture,
    health = 10,
    max_health = 10,
    damage = 1,
    spd = 5.0,
}

DefaultBerserk :: Unit {
    kind = .Berserk,
    texture = .BerserkTexture,
    health = 5,
    max_health = 5,
    damage = 2,
    spd = 10.0,
}

unit_rect :: proc(u : Unit) -> rect {
    return rect {x = u.pos.x, y = u.pos.y, width = f32(tile_size), height = f32(tile_size)}
}

draw_unit :: proc(u : Unit) {
    texture : rl.Texture2D
    rl.DrawTextureEx(state.atlas.textures[u.texture], world_pos_to_screen_pos(u.pos), 0.0, state.camera.zoom, rl.WHITE)
}

unit_set_target :: proc(u : ^Unit, tgt : v2) {
    u.target = tgt
}

update_unit :: proc(u : ^Unit) {
    if u.pos != u.target {
        diff := u.target - u.pos
        if rl.Vector2Length(diff) < u.spd {
            u.pos = u.target
        } else {
            u.pos += rl.Vector2Normalize(diff)*u.spd
        }
    }
}

place_unit :: proc(k : UnitKind, pos : v2) {
    unit : Unit
    switch k {
    case .Orc: unit = DefaultOrc;
    case .Berserk: unit = DefaultBerserk;
    }

    unit.pos = pos
    unit.target = unit.pos

    unit_grid_pos := grid_position(unit.pos + tile_size_offset, tile_size)
    target_tile := state.world[i32(unit_grid_pos.y)][i32(unit_grid_pos.x)]
    placeable := PlaceableTile
    if placeable[target_tile.kind] {
        append(&state.units, unit)
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
    selected_building : BuildingKind,

    units : [dynamic]Unit,
    selected_unit : UnitKind,

    world : ^[world_size][world_size]Tile,

    interact_state : InteractState,
    dragging : bool,
    drag_start : v2,
    drag_end : v2,
    selected_units : []^Unit,

    debug : bool,
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

    state.selected_building = .Tower
    state.selected_unit = .Orc

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
                grass_textures_choice := []TextureKind{.GrassTexture0, .GrassTexture1, .GrassTexture2, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3, .GrassTexture3}
                tile.texture = rand.choice(grass_textures_choice)
                tile.shade = 0.98+(rand.float32()*0.02)
            }
            case.Rock: {
                tile.texture = .RockTexture
                tile.shade = (1.0 - noise[(y*world_size) + x])/0.25
            }
            case.Water: {
                tile.texture = .WaterTexture
                tile.shade = (1.0 - (0.1 - noise[(y*world_size)+x]))
            }
            case.Forest: {
                tile.texture = .ForestTexture
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
                unit_set_target(u, screen_pos_to_world_pos(rl.GetMousePosition() - tile_size_offset))
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
                pos := u.pos
                return (pos.x >= state.drag_start.x && pos.x <= state.drag_end.x &&
                        pos.y >= state.drag_start.y && pos.y <= state.drag_end.y)
            })

            state.selected_units = units
            for u in units {
                rl.DrawCircleV(world_pos_to_screen_pos(u.pos), f32(tile_size/2), rl.Color{0,255,0, 50})
            }
        }
    }
    // reset buildings and enemies
    {
        if rl.IsKeyPressed(rl.KeyboardKey.R) {
            clear(&state.buildings)
            clear(&state.units)
            // does this leak memory? - probably
            state.selected_units = []^Unit{}
        }
    }
    // interact state toggling
    {
        if rl.IsKeyPressed(rl.KeyboardKey.B) {
            // does this leak memory? - probably
            state.selected_units = []^Unit{}
            if state.interact_state != .Building {
                state.interact_state = .Building
            } else {
                state.interact_state = .None
            }
        }
        if rl.IsKeyPressed(rl.KeyboardKey.G) {
            // does this leak memory? - probably
            state.selected_units = []^Unit{}
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
        min_zoom : f32 = 0.2
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
                state.selected_building = .Tower
            } else if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
                state.selected_building = .Wall
            }
        }
    }
    // spawning units
    {
        if state.interact_state == .Spawning {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                place_unit(state.selected_unit, screen_pos_to_world_pos(rl.GetMousePosition()) - tile_size_offset)
            }

            // changing selected unit
            if rl.IsKeyPressed(rl.KeyboardKey.ONE) {
                state.selected_unit = .Orc
            } else if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
                state.selected_unit = .Berserk
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
    rl.DrawText(strings.clone_to_cstring(fmt.aprintf("camera zoom: [%f]", state.camera.zoom)), 50, 70, 18, rl.BLACK)

    {
        mouse_pos := rl.GetMousePosition()
        mouse_world_pos := screen_pos_to_world_pos(mouse_pos)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse screen pos: [%f, %f]", mouse_pos.x, mouse_pos.y)), 50, 90, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("mouse world pos: [%f, %f]", mouse_world_pos.x, mouse_world_pos.y)), 50, 110, 18, rl.BLACK)
    }

    rl.DrawLine(i32(state.camera.screen_size.x/2), 0, i32(state.camera.screen_size.x/2), i32(state.camera.screen_size.y), rl.BLACK)
    rl.DrawLine(0, i32(state.camera.screen_size.y/2), i32(state.camera.screen_size.x), i32(state.camera.screen_size.y/2), rl.BLACK)

    for u in state.selected_units {
        rl.DrawLineV(world_pos_to_screen_pos(u.pos), world_pos_to_screen_pos(u.target), rl.BLACK)
    }
}

draw_gui :: proc() {
    bottom_anchor := i32(state.camera.screen_size.y)
    bottom_anchor_f := state.camera.screen_size.y
    // building ui
    {
        rl.DrawText("TOGGLE BUILDING MODE WITH <B>", 50, bottom_anchor - 30, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", building_kind_string(state.selected_building))), 50, bottom_anchor - 50, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECT BUILDING <1 ... %d>", BuildingKindN)), 50, bottom_anchor - 70, 18, rl.BLACK)

        accent := rl.WHITE
        if state.interact_state != .Building {
            accent = rl.RED
        }
        rl.DrawTextureV(state.atlas.textures[BuildingTextureKind[state.selected_building]], v2{50, bottom_anchor_f - 80 - f32(tile_size)}, accent)
    }
    // spawning ui
    {
        spawning_bottom_anchor := bottom_anchor - 80 - tile_size
        spawning_bottom_anchor_f := f32(bottom_anchor - 80 - tile_size)
        rl.DrawText("TOGGLE SPAWNING MODE WITH <G>", 50, spawning_bottom_anchor - 30, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", unit_kind_string(state.selected_unit))), 50, spawning_bottom_anchor - 50, 18, rl.BLACK)
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED UNIT <1 ... %d>", UnitKindN)), 50, spawning_bottom_anchor - 70, 18, rl.BLACK)
        accent := rl.WHITE
        if state.interact_state != .Spawning {
            accent = rl.RED
        }
        rl.DrawTextureV(state.atlas.textures[UnitKindTexture[state.selected_unit]], v2{50, spawning_bottom_anchor_f - 70 - f32(tile_size) - 10}, accent)
    }
    // dragging ui
    if state.dragging {
        pos := world_pos_to_screen_pos(state.drag_start)
        rl.DrawRectangleV(pos, world_pos_to_screen_pos(state.drag_end) - pos, rl.Color{120,120,120,50})
    }
    // selected unit gui
    for u in state.selected_units {
        pos := world_pos_to_screen_pos(u.pos)
        size := i32(f32(tile_size)*state.camera.zoom)
        rl.DrawRectangleLines(i32(pos.x), i32(pos.y), size, size, rl.BLACK)
    }

    // selected units gui 2
    if len(state.selected_units) != 0 {
        units_bottom_anchor := bottom_anchor - 30
        units_left_anchor := i32(state.camera.screen_size.x - 100)

        for unit in state.selected_units {
            rl.DrawText(strings.clone_to_cstring(unit_kind_string(unit.kind)), units_left_anchor, units_bottom_anchor, 18, rl.BLACK)
            units_bottom_anchor -= 20
        }

        rl.DrawText("SELECTED UNITS", units_left_anchor, units_bottom_anchor, 18, rl.BLACK)
    }
}

draw :: proc() {
    rl.BeginDrawing()

    rl.ClearBackground(rl.WHITE)

    draw_world_grid()


    // draw tiles
    {
        // calculate the required x and y ranges to cull all other tiles
        cull_min, cull_max := cull_camera_bounds()

        x_min := i32(cull_min.x)
        x_max := i32(cull_max.x)
        y_min := i32(cull_min.y)
        y_max := i32(cull_max.y)

        for &row in state.world[y_min:y_max] {
            for tile in row[x_min:x_max] {
                draw_tile(tile)
            }
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
