package main

import "core:fmt"
import "core:slice"
import rl "vendor:raylib"

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
    hitbox = v2{tile_size,tile_size},
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
    rl.DrawTextureEx(state.enemy_texture, pos, 0.0, state.camera.zoom, rl.WHITE)
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
