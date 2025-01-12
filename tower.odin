package main

import "core:fmt"
import "core:slice"
import rl "vendor:raylib"

Tower :: struct {
    pos: v2,
    hitbox : v2,
    health : i32,
    level : i32,
    attack_delay : i32,
    attack_timer : i32,
}

DefaultTower :: proc() -> Tower {
    return Tower {
        pos = v2{0,0},
        hitbox = v2{tile_size,tile_size},
        health = 10,
        level = 1,
        attack_delay = 10,
        attack_timer = 0,
    }
}

place_tower :: proc(tower : Tower) {
    append(&state.towers, tower)
    y_sort_towers()
    log(LOG_LEVEL.INFO, fmt.aprintf("placed tower at: %s", format_v2(tower.pos)))
}

draw_tower :: proc(tower : Tower) {
    pos := world_pos_to_screen_pos(tower.pos)
    if tower.health <= 0 {
        rl.DrawTextureEx(state.tower_texture, pos, 0.0, state.camera.zoom, rl.RED)
    } else {
        rl.DrawTextureEx(state.tower_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
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
