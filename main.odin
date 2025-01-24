package main

import "core:slice"
import "core:mem"
import "core:math"
import "core:fmt"
import "core:strings"
import "core:math/rand"
import "core:math/noise"
import "core:container/priority_queue"
import rl "vendor:raylib"

world_size :: 32
tile_size :: 64.0
tile_size_offset :: v2{tile_size/2, tile_size/2}
tile_size_offset_world :: v2{0.5, 0.5}
fps :: 60
default_width :: 800
default_height :: 600

v2 :: rl.Vector2
rect :: rl.Rectangle

// pathfinding
a_star_world :: proc(start : v2, end : v2) -> []v2 {

    AStarNode :: struct {
        pos : v2,
        weight : f32,
        parent : ^AStarNode,
    }

    heuristic :: proc(p1 : v2, p2 : v2) -> f32 {
        return rl.Vector2Distance(p1, p2)
    }

    context.allocator = context.temp_allocator
    defer(free_all(context.allocator))

    visited := make(map[v2]bool)
    queue : priority_queue.Priority_Queue(^AStarNode)
    priority_queue.init(
        &queue,
        proc(a, b : ^AStarNode) -> bool {
            return a.weight < b.weight
        },
        proc(q: []^AStarNode, i, j: int) {
            temp := q[i]
            q[i] = q[j]
            q[j] = temp
        },
        capacity = 128
        )

    // default state
    {
        default := new(AStarNode)
        default^ = AStarNode{pos = start, weight = 0, parent = nil}
        priority_queue.push(&queue, default)
    }

    for priority_queue.len(queue) != 0 {
        current : ^AStarNode = priority_queue.pop(&queue)
        if current.pos == end {
            result := make([dynamic]v2, allocator = state.alloc)

            // if slow, try to get rid of reverse somehow
            curr_node := current
            for {
                if curr_node.pos != start {
                    append(&result, curr_node.pos)
                }
                curr_node = curr_node.parent
                if curr_node == nil {
                    break
                }
            }

            slice.reverse(result[:])

            return result[:]
        }

        @(static) @(rodata)
        directions := [4]v2{v2{1,0}, v2{-1,0}, v2{0,1}, v2{0,-1}}

        if ok := current.pos in visited; ok {
            continue
        }

        visited[current.pos] = true

        neigbors : [4]Option(Tile)

        for dir, i in directions {
            new_pos := current.pos + dir
            neigbors[i] = world_get(new_pos)
        }

        for neighbor, i in neigbors {
            if neighbor.some && PlaceableTile[neighbor.val.kind] && neighbor.val.entity == nil {
                new_state := new(AStarNode)
                new_pos := current.pos + directions[i]
                if ok := new_pos in visited; ok {
                    continue
                }
                new_state^ = AStarNode{pos = new_pos, weight = current.weight + 1 + heuristic(new_pos, end), parent = current}
                priority_queue.push(&queue, new_state)
            }
        }
    }

    return nil
}

// mimicking rust types
Option :: struct($T : typeid) {
    val : T,
    some : bool,
}

Some :: proc(x : $T) -> Option(T) {
    return Option(T) {
        val = x,
        some = true,
    }
}

None :: proc($T : typeid) -> Option(T) {
    return Option(T) {
        val = T{},
        some = false,
    }
}

Unwrap :: proc(x : Option($T)) -> T {
    if !x.some {
        log(.INFO, "unwrap none option")
    }
    return x.val
}

Apply :: proc(x : Option($T), f : proc(T)) {
    if !x.some {
        return
    } else {
        f(x.val)
    }
}

// camera for rendering world
Camera :: struct {
    fps : i32,
    pos : v2,
    zoom : f32,
    screen_size : v2,
}

// utility function to highlight hovered tile
highlight_tile :: proc(pos : v2) {
    world_pos := snap_to_grid(screen_pos_to_world_pos(pos), 1.0)
    rl.DrawRectangleV(world_pos_to_screen_pos(world_pos), v2{tile_size,tile_size} * state.camera.zoom, rl.Color{220,220,220,120})
}

// snaps position to a grid
snap_to_grid :: proc(pos : v2, grid_size : f32) -> v2 {
    return v2{math.floor(pos.x / grid_size)*grid_size, math.floor(pos.y / grid_size)*grid_size}
}

normalize_to_grid :: proc(pos : v2, grid_size : f32) -> v2 {
    return v2{math.floor(pos.x / grid_size), math.floor(pos.y / grid_size)}
}

// transforms screen coordinates to world coordinates
screen_pos_to_world_pos :: proc(pos : v2) -> v2 {
    //                                offset by half screen size        transform to right scale
    return state.camera.pos + ((pos - state.camera.screen_size / 2) / tile_size / state.camera.zoom)
}

// transforms world coordinates to screen coordinates
world_pos_to_screen_pos :: proc(pos : v2) -> v2 {
    screen_center := state.camera.screen_size/2
    diff := pos - state.camera.pos
    return screen_center + (diff * state.camera.zoom * tile_size)
}

// returns the bounds the camera can render stuff in (inclusive)
cull_camera_bounds :: proc() -> (v2, v2) {
    y_min := min(world_size - 1, max(0, i32(math.floor((state.camera.pos.y - (state.camera.screen_size.y / 2 / state.camera.zoom / tile_size))))))
    y_max := min(world_size - 1, y_min + i32(math.ceil(state.camera.screen_size.y / tile_size / state.camera.zoom)) + 1)

    x_min := min(world_size - 1, max(0, i32(math.floor((state.camera.pos.x - (state.camera.screen_size.x / 2 / state.camera.zoom / tile_size))))))
    x_max := min(world_size - 1, x_min + i32(math.ceil(state.camera.screen_size.x / tile_size / state.camera.zoom)) + 1)
    return v2{f32(x_min), f32(y_min)}, v2{f32(x_max), f32(y_max)}
}

// all the texture ids
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

// atlas to hold all the textures
TextureAtlas :: struct {
    textures : [TextureKind]rl.Texture2D
}

// load textures from disk
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

// free the GPU memory
deinit_texture_atlas :: proc() {
    for texture in state.atlas.textures {
        rl.UnloadTexture(texture)
    }
}

// state of the whole game
GameState :: struct {
    // graphics stuff
    camera : Camera,
    atlas : TextureAtlas,

    // state stuff
    world : ^[world_size][world_size]Tile,
    buildings : [dynamic]^Building,
    units : [dynamic]^Unit,
    interact_state : InteractState,

    // various utilities
    debug : bool,
    alloc : mem.Allocator,
}

NoneState :: struct {}

ControllingState :: struct {
    selected : []^Unit,
}

SpawningState :: struct {
    selected : UnitKind
}

BuildingState :: struct {
    selected : BuildingKind
}

DraggingState :: struct {
    start : v2,
    end : v2,
}

InteractState :: union {
    NoneState,
    ControllingState,
    DraggingState,
    SpawningState,
    BuildingState,
}

StateGet :: proc($T : typeid) -> Option(T) {
    #partial switch &s in &state.interact_state {
    case T: {
        return Some(s)
    }
    }
    return None(T)
}

StateSetNone :: proc() {
    switch &s in &state.interact_state {
    case NoneState : return
    case ControllingState : {
        delete(s.selected, state.alloc)
        state.interact_state = NoneState{}
    }
    case DraggingState, SpawningState, BuildingState : {
        state.interact_state = NoneState{}
    }
    }
}

// world manipulation functions
world_get :: proc(pos : v2) -> Option(Tile) {
    if i32(pos.x) >= world_size || i32(pos.x) < 0 || i32(pos.y) >= world_size || i32(pos.y) < 0 { return None(Tile) }
    return Some(state.world[i32(pos.y)][i32(pos.x)])
}

world_get_mut :: proc(pos : v2) -> Option(^Tile) {
    if i32(pos.x) >= world_size || i32(pos.x) < 0 || i32(pos.y) >= world_size || i32(pos.y) < 0 { return None(^Tile) }
    return Some(&state.world[i32(pos.y)][i32(pos.x)])
}

world_set :: proc(pos : v2, t : Tile) -> bool {
    if i32(pos.x) >= world_size || i32(pos.x) < 0 || i32(pos.y) >= world_size || i32(pos.y) < 0 { return false }
    state.world[i32(pos.y)][i32(pos.x)] = t
    return true
}

// global state object
state : GameState

// some interpolations functions
smoothstep :: proc(t : f32) -> f32 {
    return t * t * t * (t * (t * 6 - 15) + 10)
}

lerp :: proc(a : f32, b : f32, t : f32) -> f32 {
    return a + t * (b - a)
}

// world generation functions
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

// mapping noise to terrain tile
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

// world generation
generate_world :: proc() {
    size := size_of(Tile) * world_size * world_size
    tiles_ptr, err := mem.alloc(size, mem.DEFAULT_ALIGNMENT, state.alloc)
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
                pos = v2{f32(x), f32(y)},
                entity = nil,
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
}

// some util functions
pos2rect :: proc(p1 : v2, p2 : v2) -> rect {
    min_x := min(p1.x, p2.x)
    min_y := min(p1.y, p2.y)
    max_x := max(p1.x, p2.x)
    max_y := max(p1.y, p2.y)
    return rect{min_x, min_y, max_x - min_x, max_y - min_y}
}

map_mut :: proc(xs: []$T, fn: proc(^T) -> $R) -> []R {
    result := make([]R, len(xs))
    for &x, i in xs {
        result[i] = fn(&x)
    }
    return result
}

// entities
Entity :: union {
    Building,
    Unit,
}

BuildingKind :: enum {
    Tower,
    Wall,
}

@(rodata)
BuildingKindString := [BuildingKind]string {
    .Tower = "Tower",
    .Wall = "Wall",
}

@(rodata)
BuildingTextureKind := [BuildingKind]TextureKind {
    .Tower = .TowerTexture,
    .Wall = .WallTexture,

}
BuildingKindN :: len(BuildingKind)

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

// draws a give building on the screen
draw_building :: proc(b : ^Building) {
    pos := world_pos_to_screen_pos(b.pos)
    accent : rl.Color
    switch {
    case b.health <= 0: accent = rl.RED
    case: accent = rl.WHITE
    }
    rl.DrawTextureEx(state.atlas.textures[b.texture], pos, 0.0, state.camera.zoom, accent)
}

// places building in the world if possible at the given world position
place_building :: proc(k : BuildingKind, p : v2) -> bool {
    building : ^Building = new(Building, allocator = state.alloc)

    switch k {
    case .Tower: building^ = DefaultTower;
    case .Wall: building^ = DefaultWall;
    }

    building.pos = p

    target_tile := world_get_mut(p)
    if !target_tile.some { return false }
    if PlaceableTile[target_tile.val.kind] {
        append(&state.buildings, building)
        target_tile.val.entity = cast(^Entity)building
        return true
    } else {
        return false
    }
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

UnitKindN :: len(UnitKind)

@(rodata)
UnitKindString := [UnitKind]string {
    .Orc = "Orc",
    .Berserk = "Berserk",
}

Unit :: struct {
    kind: UnitKind,
    texture : TextureKind,
    pos : v2,
    health : i32,
    max_health : i32,
    damage : i32,
    spd : f32,
    target : v2,
    path : []v2,
    path_idx : i32,
    tile : ^Tile,
}

DefaultOrc :: Unit {
    kind = .Orc,
    texture = .OrcTexture,
    health = 10,
    max_health = 10,
    damage = 1,
    spd = 0.05,
    path = nil,
    path_idx = 0,
}

DefaultBerserk :: Unit {
    kind = .Berserk,
    texture = .BerserkTexture,
    health = 5,
    max_health = 5,
    damage = 2,
    spd = 0.1,
    path = nil,
    path_idx = 0,
}

draw_unit :: proc(u : ^Unit) {
    rl.DrawTextureEx(state.atlas.textures[u.texture], world_pos_to_screen_pos(u.pos), 0.0, state.camera.zoom, rl.WHITE)
}

unit_rect_world :: proc(u : ^Unit) -> rect {
    return rect{u.pos.x, u.pos.y, 1.0, 1.0}
}

place_unit :: proc(k : UnitKind, p : v2) -> bool {
    unit := new(Unit, allocator = state.alloc)
    switch k {
    case .Orc: unit^ = DefaultOrc;
    case .Berserk: unit^ = DefaultBerserk;
    }

    unit.pos = p
    unit.target = p

    target_tile := world_get_mut(p)
    if !target_tile.some { return false }
    if PlaceableTile[target_tile.val.kind] && target_tile.val.entity == nil {
        unit_set_tile(unit, target_tile.val)
        append(&state.units, unit)
        return true
    } else {
        return false
    }
}

unit_set_tile :: proc(u : ^Unit, t : ^Tile) {
    if u.tile != nil {
        u.tile.entity = nil
    }
    u.tile = t
    t.entity = cast(^Entity)u
}

unit_set_target :: proc(u : ^Unit, tgt : v2) {
    u.target = tgt
}

unit_calculate_path :: proc(u : ^Unit) {
    path := a_star_world(snap_to_grid(u.pos, 1.0), u.target)
    if u.path != nil && len(u.path) != 0 {
        delete(u.path)
    }
    u.path = path
    u.path_idx = 0
    if u.path != nil && len(u.path) != 0 {
        unit_set_tile(u, world_get_mut(u.path[0]).val)
    }
}

update_unit :: proc(u : ^Unit) {
    if u.path != nil {
        path_node := u.path[u.path_idx]
        diff := path_node - u.pos
        if rl.Vector2Length(diff) < u.spd {
            u.pos = path_node
            u.path_idx += 1
            if u.path_idx >= i32(len(u.path)) {
                // free the memory
                delete(u.path)
                u.path = nil
                u.path_idx = 0
                return
            }

            next_tile := world_get_mut(u.path[u.path_idx]).val
            // check if next tile reserved
            if next_tile.entity == nil {
                unit_set_tile(u, world_get_mut(u.path[u.path_idx]).val)
            } else {
                unit_set_tile(u, world_get_mut(u.pos).val)
                unit_calculate_path(u)
            }
        } else {
            u.pos += rl.Vector2Normalize(diff)  * u.spd
        }
    }
}

// tile stuff
TileKind :: enum {
    Grass,
    Water,
    Forest,
    Rock,
}

@(rodata)
TileKindString := [TileKind]string {
    .Rock = "Rock",
    .Forest = "Forest",
    .Water = "Water",
    .Grass = "Grass",
}

@(rodata)
PlaceableTile := [TileKind]bool {
    .Grass = true,
    .Water = false,
    .Forest = false,
    .Rock = false,
}

Tile :: struct {
    pos : v2,
    kind : TileKind,
    texture : TextureKind,
    shade: f32,
    entity : ^Entity
}

draw_tile :: proc(t : Tile) {
    s := u8(255.0 * t.shade)
    if state.debug && t.entity != nil { s = 0 }
    rl.DrawTextureEx(state.atlas.textures[t.texture], world_pos_to_screen_pos(t.pos), 0.0, state.camera.zoom, rl.Color{s, s, s, 255})
}

// game state intialization
init_game_state :: proc(alloc := context.allocator) {
    state.camera = Camera {
        pos = v2{0,0},
        zoom = 1.0,
    }

    state.alloc = alloc

    state.interact_state = NoneState{}

    state.debug = false

    if state.camera.screen_size.x == 0.0 && state.camera.screen_size.y == 0.0 {
        state.camera.screen_size = v2{f32(default_width), f32(default_height)}
    }

    generate_world()
}

// display state initialization
init_display :: proc(fullscreen : bool) {
    rl.SetConfigFlags(rl.ConfigFlags{rl.ConfigFlag.WINDOW_RESIZABLE, rl.ConfigFlag.VSYNC_HINT})
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

// input handling : TODO refactor
handle_input :: proc() {
    // dragging behavior
    #partial switch &s in state.interact_state {
    case ControllingState: {
        if rl.IsMouseButtonPressed(.LEFT) {
            StateSetNone()
        }
        if rl.IsKeyPressed(rl.KeyboardKey.M) || rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
            if t := world_get(screen_pos_to_world_pos(rl.GetMousePosition()));
            t.some && PlaceableTile[t.val.kind] {
                target := t.val.pos
                for &u in s.selected {
                    unit_set_target(u, target)
                    unit_calculate_path(u)
                }
                for &u in s.selected {
                    if u.path == nil {
                        for &u in s.selected {
                            if u.path == nil {
                                unit_set_target(u, target)
                                unit_calculate_path(u)
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    case DraggingState: {
        s.end = screen_pos_to_world_pos(rl.GetMousePosition())

        if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
            units, _ := slice.filter(state.units[:], proc (u : ^Unit) -> bool {
                s := StateGet(DraggingState)
                if !s.some {return false} else {
                    select_rect := pos2rect(s.val.start, s.val.end)
                    return rl.CheckCollisionPointRec(u.pos + tile_size_offset_world, select_rect)
                }
                return false
            }, allocator = state.alloc)

            state.interact_state = ControllingState{
                selected = units
            }

            if len(units) == 0 {
                StateSetNone()
            }
        }
    }
    case NoneState: {
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            StateSetNone()
            state.interact_state = DraggingState{
                start = screen_pos_to_world_pos(rl.GetMousePosition()),
                end = screen_pos_to_world_pos(rl.GetMousePosition()),
            }
        }
        if rl.IsKeyPressed(rl.KeyboardKey.B) {
            state.interact_state = BuildingState{
                selected = .Tower
            }
        }

        if rl.IsKeyPressed(rl.KeyboardKey.G) {
            state.interact_state = SpawningState{
                selected = .Orc
            }
        }
    }
    // placing buildings
    case BuildingState:{
        if rl.IsMouseButtonPressed(.LEFT) {
            place_building(s.selected, snap_to_grid(screen_pos_to_world_pos(rl.GetMousePosition()), 1.0))
        }

        if rl.IsKeyPressed(.B) {
            StateSetNone()
        }

        if rl.IsKeyPressed(.G) {
            state.interact_state = SpawningState{}
        }

        // changing selected building
        if rl.IsKeyPressed(.ONE) {
            s.selected = .Tower
        } else if rl.IsKeyPressed(.TWO) {
            s.selected = .Wall
        }
    }
    // spawning units
    case SpawningState: {
        if rl.IsMouseButtonPressed(.LEFT) {
            place_unit(s.selected, snap_to_grid(screen_pos_to_world_pos(rl.GetMousePosition()), 1.0))
        }

        if rl.IsKeyPressed(.G) {
            StateSetNone()
        }

        if rl.IsKeyPressed(.B) {
            state.interact_state = BuildingState{}
        }

        // changing selected unit
        if rl.IsKeyPressed(.ONE) {
            s.selected = .Orc
        } else if rl.IsKeyPressed(.TWO) {
            s.selected = .Berserk
        }
    }
    }
    // ---------------- state independent keymaps ------------------
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

        state.camera.pos += rl.Vector2Normalize(diff) * 10 / state.camera.zoom * rl.GetFrameTime()
    }
    // reset buildings and units
    {
        if rl.IsKeyPressed(rl.KeyboardKey.R) {
            clear(&state.buildings)
            clear(&state.units)
            StateSetNone()
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

// game update loop
update :: proc() {

    // update screen dimensions
    if rl.IsWindowResized() {
        width := f32(rl.GetScreenWidth())
        height := f32(rl.GetScreenHeight())

        state.camera.screen_size = v2{width, height}
    }

    handle_input()
    for u in state.units {
        update_unit(u)
    }
}

// draws world grid background
draw_world_grid :: proc() {
    screen_size := state.camera.screen_size
    top_left := screen_pos_to_world_pos(v2{0, 0})
    bottom_right := screen_pos_to_world_pos(screen_size)

    col1 := rl.Color{180, 180, 180, 255}
    col2 := rl.Color{200, 200, 200, 255}
    for y in math.floor(top_left.y)..<math.ceil(bottom_right.y) {
        for x in math.floor(top_left.x)..<math.ceil(bottom_right.x) {
            world_pos := v2{f32(x), f32(y)}

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

// simple debug info
draw_debug_info :: proc() {

    // important
    context.allocator = context.temp_allocator
    defer free_all(context.allocator)

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

    // unit info hover
    {
        for unit in state.units {
            mouse_pos := screen_pos_to_world_pos(rl.GetMousePosition())
            if rl.CheckCollisionPointRec(mouse_pos, unit_rect_world(unit)) {
                rl.DrawText(strings.clone_to_cstring(fmt.aprintf("unit kind : %s", UnitKindString[unit.kind])), i32(state.camera.screen_size.x - 150), 50, 18, rl.BLACK)
                break
            }
        }
    }

    #partial switch &s in &state.interact_state {
    case ControllingState: {
        for u in s.selected {
            rl.DrawLineV(world_pos_to_screen_pos(u.pos), world_pos_to_screen_pos(u.target), rl.BLACK)
            draw_a_star_path(u.path[u.path_idx:])
        }
    }
    }
}

// draw the gui
draw_gui :: proc() {

    // very important step

    context.allocator = context.temp_allocator
    free_all(context.allocator)

    border_padding :: 30
    gui_pos_y := i32(state.camera.screen_size.y) - border_padding
    gui_pos_x :: 50
    texture_height :: 80
    spacing_height :: 5
    font_size :: 18

    #partial switch s in state.interact_state {
    case BuildingState : {
        rl.DrawText("TOGGLE BUILDING MODE WITH <B>", gui_pos_x, gui_pos_y, font_size, rl.BLACK)

        gui_pos_y -= font_size + spacing_height 
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", BuildingKindString[s.selected])), gui_pos_x, gui_pos_y, font_size, rl.BLACK)

        gui_pos_y -= font_size + spacing_height
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECT BUILDING <1 ... %d>", BuildingKindN)), gui_pos_x, gui_pos_y, font_size, rl.BLACK)

        accent := rl.WHITE
        if _, ok := state.interact_state.(BuildingState); !ok {
            accent = rl.RED
        }
        gui_pos_y -= texture_height + spacing_height
        rl.DrawTextureV(state.atlas.textures[BuildingTextureKind[s.selected]], v2{f32(gui_pos_x), f32(gui_pos_y)}, accent)
    }
    case SpawningState : {
        rl.DrawText("TOGGLE SPAWNING MODE WITH <G>", gui_pos_x, gui_pos_y, font_size, rl.BLACK)

        gui_pos_y -= font_size + spacing_height
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED: %s", UnitKindString[s.selected])), gui_pos_x, gui_pos_y, font_size, rl.BLACK)

        gui_pos_y -= font_size + spacing_height
        rl.DrawText(strings.clone_to_cstring(fmt.aprintf("SELECTED UNIT <1 ... %d>", UnitKindN)), gui_pos_x, gui_pos_y, font_size, rl.BLACK)
        accent := rl.WHITE
        if _, ok := state.interact_state.(SpawningState); !ok {
            accent = rl.RED
        }

        gui_pos_y -= texture_height + spacing_height
        rl.DrawTextureV(state.atlas.textures[UnitKindTexture[s.selected]], v2{f32(gui_pos_x), f32(gui_pos_y)}, accent)
    }
    case DraggingState : {
        rect := pos2rect(s.start, s.end)
        lc := world_pos_to_screen_pos(v2{rect.x, rect.y})
        rect.x = lc.x
        rect.y = lc.y
        rect.width *= state.camera.zoom * tile_size
        rect.height *= state.camera.zoom * tile_size
        rl.DrawRectangleRec(rect, rl.Color{120,120,120,120})
    }
    case ControllingState : {
        for u in s.selected {
            pos := world_pos_to_screen_pos(u.pos)
            size := i32(tile_size*state.camera.zoom)
            rl.DrawRectangleLines(i32(pos.x), i32(pos.y), size, size, rl.BLACK)
        }

        if len(s.selected) != 0 {
            gui_pos_x := i32(state.camera.screen_size.x - 200)

            for u in s.selected {
                rl.DrawText(strings.clone_to_cstring(UnitKindString[u.kind]), gui_pos_x, gui_pos_y, font_size, rl.BLACK)
                gui_pos_y -= font_size + spacing_height
            }

            rl.DrawText("SELECTED UNITS", gui_pos_x, gui_pos_y, font_size, rl.BLACK)
        }
    }
    }
}

// draws the path
draw_a_star_path :: proc(path : []v2) {
    for p in path {
        rl.DrawRectangleV(world_pos_to_screen_pos(p), v2{tile_size, tile_size} * state.camera.zoom, rl.Color{255,0,0,80})
    }
}

// draw the whole world and ui
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

    #partial switch s in state.interact_state {
    case BuildingState, SpawningState : highlight_tile(rl.GetMousePosition())
    }

    draw_gui()
    if state.debug {
        draw_debug_info()
    }

    rl.EndDrawing()
}

// main game loop
main :: proc() {
    init_display(false)
    log(LOG_LEVEL.INFO, "display initialized")

    init_game_state()
    log(LOG_LEVEL.INFO, "game state initialized")
    defer free_all(state.alloc)

    init_texture_atlas()
    log(LOG_LEVEL.INFO, "texture atlas initialized")
    defer deinit_texture_atlas()

    for !rl.WindowShouldClose() {
        update()
        draw()
    }
}
