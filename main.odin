package main

import rl "vendor:raylib"
import "core:math"
import "core:fmt"
import "core:slice"

v2 :: rl.Vector2

format_v2 :: proc(v : v2) -> string {
    return fmt.aprint("[%f, %f]", v.x, v.y)
}

width: i32 = 800;
height: i32 = 600;
fps :: 60

// initializes the display with some default values
init_display :: proc(fullscreen : bool) {
    rl.InitWindow(width, height, "Hello, raylib!")
    rl.SetTargetFPS(fps)
    if !fullscreen {
        return
    }

    monitor := rl.GetCurrentMonitor()
    width = rl.GetMonitorWidth(monitor)
    height = rl.GetMonitorHeight(monitor)
    rl.SetWindowSize(width, height)
    rl.SetWindowPosition(0,0)
    rl.SetTargetFPS(60)
}

Tower :: struct {
    pos: v2,
    hitbox : v2,
    health : i32,
    level : i32,
    attack_delay : i32,
    attack_timer : i32,
}

DefaultTower :: Tower {
    pos = v2{0,0},
    hitbox = v2{64,64},
    health = 10,
    level = 1,
    attack_delay = 10,
    attack_timer = 0,
}

place_tower :: proc(tower : Tower) {
    append(&state.towers, tower)
    y_sort_towers()
    log(LOG_LEVEL.INFO, fmt.aprintf("placed tower at: %s", format_v2(tower.pos)))
}

draw_tower :: proc(tower : Tower) {
    pos := world_pos_to_screen_pos(tower.pos)
    if tower.health <= 0 {
        rl.DrawTextureV(state.tower_texture, pos, rl.RED)
    } else {
        rl.DrawTextureV(state.tower_texture, pos, rl.WHITE)
    }
}

y_sort_towers :: proc() {
    sort_by_y :: proc(a, b : Tower) -> bool {
        if a == (Tower{}) {
            return true
        }
        if b == (Tower{}) {
            return false
        }
        return a.pos.y < b.pos.y
    }

    slice.sort_by(state.towers[:], sort_by_y)
}

closest_tower :: proc(origin : v2) -> ^Tower {
    if len(state.towers) == 0 {
        return nil
    }

    best : ^Tower = &state.towers[0]
    min_dist := rl.Vector2Length(state.towers[0].pos - origin + state.towers[0].hitbox/2)
    for &tower in state.towers[1:] {
        dist := rl.Vector2Length(tower.pos - origin + tower.hitbox/2)
        if (dist < min_dist) {
            min_dist = dist
            best = &tower
        }
    }

    return best
}

Enemy :: struct {
    pos : v2,
    hitbox : v2,
    vel : f32,
    health : i32,
    damage : i32,
    level : i32,
    attack_delay : i32,
    attack_timer : i32,
    target : ^Tower,
}

DefaultEnemy :: Enemy {
    pos = v2{0,0},
    vel = 2.0,
    hitbox = v2{64,64},
    health = 10,
    damage = 1,
    level =  1,
    attack_delay = 10,
    attack_timer = 0,
    target = nil,
}

update_enemy :: proc(enemy : ^Enemy) {
    if enemy.attack_timer > 0 {
        enemy.attack_timer -= 1
    }

    if enemy.target == nil {
        return
    }

    diff := enemy.target.pos - enemy.pos
    tower_radius := rl.Vector2Length(enemy.target.hitbox)/2
    if rl.Vector2Length(diff) < tower_radius {
        // attack
        if enemy.attack_timer == 0 {
            enemy.attack_timer = enemy.attack_delay
            enemy.target.health -= enemy.damage
            if enemy.target.health <= 0 {
                enemy.target = nil
            }
        }

        return
    }

    diff = rl.Vector2Normalize(diff)

    enemy.pos += diff*enemy.vel
}

place_enemy :: proc(enemy : Enemy) {
    append(&state.enemies, enemy)
    y_sort_enemies()
    log(LOG_LEVEL.INFO, fmt.aprintf("placed enemy at: %s", format_v2(enemy.pos)))
}

draw_enemy :: proc(enemy: Enemy) {
    pos := world_pos_to_screen_pos(enemy.pos)
    rl.DrawTextureV(state.enemy_texture, pos, rl.WHITE)
}

y_sort_enemies :: proc() {
    sort_by_y :: proc(a, b : Enemy) -> bool {
        if a == (Enemy{}) {
            return true
        }
        if b == (Enemy{}) {
            return false
        }
        return a.pos.y < b.pos.y
    }

    slice.sort_by(state.enemies[:], sort_by_y)
}

GameState :: struct {
    camera_pos : v2,
    towers : [dynamic]Tower,
    tower_texture : rl.Texture2D,

    enemies : [dynamic]Enemy,
    enemy_texture : rl.Texture2D,
}

state := GameState {
        camera_pos = v2{0,0},
        towers = [dynamic]Tower{},
}

init_assets :: proc() {
    state.tower_texture = rl.LoadTexture("./tower.png")
    state.enemy_texture = rl.LoadTexture("./enemy.png")
}

screen_pos_to_world_pos :: proc(pos : v2) -> v2 {
    diff := v2{f32(width/2), f32(height/2)}
    lc := state.camera_pos - diff
    return lc + pos
}

world_pos_to_screen_pos :: proc(pos : v2) -> v2 {
    diff := v2{f32(width/2), f32(height/2)}
    lc := state.camera_pos - diff
    return pos - lc
}

snap_to_grid :: proc(pos : v2, grid_size : i32) -> v2 {
    return v2{math.floor(pos.x / f32(grid_size))*f32(grid_size), math.floor(pos.y / f32(grid_size))*f32(grid_size)}
}

handle_keys :: proc() {
    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        tower := DefaultTower
        mouse_pos := rl.GetMousePosition()
        world_space_pos := screen_pos_to_world_pos(mouse_pos)
        tower.pos = snap_to_grid(world_space_pos, 64)
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
}

update :: proc() {
    for &enemy in state.enemies {
        update_enemy(&enemy)
    }
}

draw :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    for tower in state.towers {
        draw_tower(tower)
    }

    for enemy in state.enemies {
        draw_enemy(enemy)
    }

    rl.DrawText("tower defense test", 50, 50, 18, rl.BLACK)

    rl.EndDrawing()
}

main :: proc() {
    init_display(false)
    init_assets()

    log(LOG_LEVEL.INFO, "display initialized")

    for !rl.WindowShouldClose() {
        handle_keys()
        update()
        draw()
    }
}
