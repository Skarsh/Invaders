package main

import "core:fmt"
import math "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:math/rand"
import time "core:time"
import rl "vendor:raylib"

Window :: struct {
	name:          cstring,
	width:         i32,
	height:        i32,
	fps:           i32,
	control_flags: rl.ConfigFlags,
}

Player :: struct {
	sprite:          rl.Rectangle,
	rect:            rl.Rectangle,
	num_lives:       i32,
	velocity:        f32,
	shooting_freq:   f32,
	last_shoot_time: i64,
	last_hit_time:   i64,
}

Enemy :: struct {
	sprite:    rl.Rectangle,
	rect:      rl.Rectangle,
	health:    i32,
	velocity:  f32,
	attacking: bool,
}

Bullet :: struct {
	sprite:               rl.Rectangle,
	rect:                 rl.Rectangle,
	damage:               i32,
	velocity:             f32,
	animation_time_start: i64,
	state:                enum {
		NORMAL,
		SMALL_EXPLOSION,
		LARGE_EXPLOSION,
	},
}

Game :: struct {
	last_tick:              time.Time,
	pause:                  bool,
	colors:                 []rl.Color,
	width:                  i32,
	height:                 i32,
	player:                 Player,
	enemies:                [dynamic]Enemy,
	player_bullets:         [dynamic]Bullet,
	initialized:            bool,
	won:                    bool,
	lost:                   bool,
	last_enemy_attack_time: i64,
}

UserInput :: struct {
	left_mouse_clicked:  bool,
	right_mouse_clicked: bool,
	toggle_pause:        bool,
	mouse_pos:           [2]f32,
}

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 1024

RESOLUTION_MULTIPLIER :: 5

NUM_ENEMIES :: 10
NS_PER_SEC :: 1_000_000_000
NS_PER_MS :: 1_000_000


PLAYER_SPRITE :: rl.Rectangle {
	x      = 0,
	y      = 1,
	width  = 8,
	height = 7,
}

BULLET_SPRITE :: rl.Rectangle {
	x      = 11,
	y      = 19,
	width  = 2,
	height = 3,
}

BULLET_SMALL_EXPLOSION_SPRITE :: rl.Rectangle {
	x      = 10,
	y      = 26,
	width  = 4,
	height = 4,
}

BULLET_LARGE_EXPLOSION_SPRITE :: rl.Rectangle {
	x      = 8,
	y      = 32,
	width  = 8,
	height = 8,
}

SIMPLE_ENEMY_SPRITE :: rl.Rectangle {
	x      = 33,
	y      = 0,
	width  = 6,
	height = 8,
}

process_user_input :: proc(user_input: ^UserInput, window: Window) {
	m_pos := rl.GetMousePosition()

	user_input^ = UserInput {
		left_mouse_clicked  = rl.IsMouseButtonDown(.LEFT),
		right_mouse_clicked = rl.IsMouseButtonDown(.RIGHT),
		toggle_pause        = rl.IsKeyPressed(.SPACE),
		mouse_pos           = m_pos,
	}

}

// TODO(Thomas): Globals like this are not that nice
angle: f32 = 0.0
attack_cooldown_duration: i64 = 5_000_000_000
hit_cooldown_duration: i64 = 1_000_000_000
small_explosion_duration: i64 = 25_000_000
large_explosion_duration: i64 = 25_000_000

update_game :: proc(
	game: ^Game,
	player_shoot_sound: rl.Sound,
	invader_killed_sound: rl.Sound,
	explosion_sound: rl.Sound,
) {
	using glsl

	// Update player
	now := time.now()
	// dt in sec
	dt := f32(now._nsec - game.last_tick._nsec) / NS_PER_SEC
	game.last_tick = time.now()

	angle += 0.05


	// TODO(Thomas): This is currently framerate dependent movement
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		game.player.rect.x += game.player.velocity * dt
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		game.player.rect.x -= game.player.velocity * dt
	}
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		game.player.rect.y -= game.player.velocity * dt
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		game.player.rect.y += game.player.velocity * dt
	}

	if rl.IsKeyDown(.SPACE) {
		// TODO(Thomas): This is trash, convert to seconds and calculate that way or something
		if f32(now._nsec - game.player.last_shoot_time) >
		   NS_PER_SEC / game.player.shooting_freq {
			rl.PlaySound(player_shoot_sound)
			append(
				&game.player_bullets,
				Bullet {
					sprite = BULLET_SPRITE,
					rect = rl.Rectangle {
						x = game.player.rect.x,
						y = game.player.rect.y,
						width = BULLET_SPRITE.width * RESOLUTION_MULTIPLIER,
						height = BULLET_SPRITE.height * RESOLUTION_MULTIPLIER,
					},
					damage = 10,
					velocity = 1200,
				},
			)
			game.player.last_shoot_time = now._nsec
		}
	}

	// Update bullets
	for &bullet, bullet_idx in game.player_bullets {

		// This animation code is VERY temporary
		if now._nsec >
			   bullet.animation_time_start + small_explosion_duration &&
		   now._nsec < bullet.animation_time_start + large_explosion_duration {
			bullet.state = .LARGE_EXPLOSION
		}

		if now._nsec >
			   bullet.animation_time_start + large_explosion_duration &&
		   now._nsec <
			   bullet.animation_time_start +
				   large_explosion_duration +
				   small_explosion_duration {
			bullet.state = .SMALL_EXPLOSION
		}

		if now._nsec >
			   bullet.animation_time_start +
				   large_explosion_duration +
				   small_explosion_duration &&
		   bullet.state != .NORMAL {
			unordered_remove(&game.player_bullets, bullet_idx)
		}

		// Bullet is outside the screen remove it and continue to next bullet
		if bullet.rect.x < 0 ||
		   bullet.rect.x > SCREEN_WIDTH ||
		   bullet.rect.y < 0 ||
		   bullet.rect.y > SCREEN_HEIGHT {
			unordered_remove(&game.player_bullets, bullet_idx)
			continue
		}

		// If bullet hit enemy, make the enemy take damage
		for &enemy, enemy_idx in game.enemies {
			if rl.CheckCollisionRecs(bullet.rect, enemy.rect) {
				bullet.animation_time_start = time.now()._nsec
				bullet.state = .SMALL_EXPLOSION
				rl.PlaySound(explosion_sound)
				enemy.health -= bullet.damage
				if (enemy.health <= 0) {
					rl.PlaySound(invader_killed_sound)
					unordered_remove(&game.enemies, enemy_idx)
					if len(game.enemies) == 0 {
						game.won = true
					}
				}
			}
		}

		#partial switch bullet.state {
		case .NORMAL:
			bullet.rect.y -= bullet.velocity * dt
		}
	}

	random_enemy_idx: i32
	if !game.initialized {
		game.last_enemy_attack_time = now._nsec
		game.initialized = true
	} else {
		if now._nsec > game.last_enemy_attack_time + attack_cooldown_duration {
			random_enemy_idx = rl.GetRandomValue(0, i32(len(game.enemies)))
			if (random_enemy_idx < i32(len(game.enemies))) {
				game.enemies[random_enemy_idx].attacking = true
				game.last_enemy_attack_time = now._nsec
			}
		}
	}

	// Update enemies
	for &enemy in game.enemies {
		// Check if player collides with enemy
		if rl.CheckCollisionRecs(game.player.rect, enemy.rect) {
			if now._nsec > game.player.last_hit_time + hit_cooldown_duration {
				if (game.player.num_lives > 0) {
					game.player.num_lives -= 1
					game.player.last_hit_time = now._nsec
					if game.player.num_lives == 0 {
						game.lost = true
					}
				}
			}
		}

		// TODO(Thomas): This is currently working a bit weird.
		// I would like the enemies to rotate in a circle based on a radius and
		// then have velocity be the angular velocity or something like that
		// Problem with this now is that it changes depending on the dt, so different
		// framerates have different behaviour
		if !enemy.attacking {
			enemy.rect.x += math.cos(angle) * enemy.velocity * dt
			enemy.rect.y += math.sin(angle) * enemy.velocity * dt
		} else {
			player_vec := vec2{game.player.rect.x, game.player.rect.y}
			enemy_vec := vec2{enemy.rect.x, enemy.rect.y}

			dir := normalize_vec2(player_vec - enemy_vec)

			enemy.rect.x += dir.x * enemy.velocity * dt
			enemy.rect.y += dir.y * enemy.velocity * dt
		}
	}
}


draw_player :: proc(
	player: Player,
	texture: rl.Texture2D,
	src_rect: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
) {
	rl.DrawTexturePro(
		texture,
		src_rect,
		player.rect,
		origin,
		rotation,
		rl.WHITE,
	)
}

draw_bullet :: proc(
	bullet: Bullet,
	texture: rl.Texture2D,
	src_rect: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
) {
	rl.DrawTexturePro(
		texture,
		src_rect,
		bullet.rect,
		origin,
		rotation,
		rl.WHITE,
	)
}

draw_enemy :: proc(
	enemy: Enemy,
	texture: rl.Texture2D,
	src_rect: rl.Rectangle,
	origin: rl.Vector2,
	rotation: f32,
) {
	rl.DrawTexturePro(
		texture,
		src_rect,
		enemy.rect,
		origin,
		rotation,
		rl.WHITE,
	)
}

main :: proc() {
	window := Window {
		"Definitely Not Space Invaders!",
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		144,
		rl.ConfigFlags{.WINDOW_RESIZABLE},
	}


	user_input: UserInput

	rl.InitWindow(window.width, window.height, window.name)
	defer rl.CloseWindow()

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	shoot_sound := rl.LoadSound("./assets/sounds/shoot.wav")
	rl.SetSoundVolume(shoot_sound, 0.05)

	invader_killed_sound := rl.LoadSound("./assets/sounds/invaderkilled.wav")
	rl.SetSoundVolume(invader_killed_sound, 0.05)

	explosion_sound := rl.LoadSound("./assets/sounds/explosion.wav")
	rl.SetSoundVolume(explosion_sound, 0.05)

	music := rl.LoadMusicStream("./assets/music/road_to_nowhere_long.mp3")

	rl.SetWindowState(window.control_flags)
	rl.SetTargetFPS(window.fps)


	invaders_sprite_sheet := rl.LoadTexture(
		"./assets/textures/pico8_invaders_sprites_LARGE_transparent.png",
	)
	defer rl.UnloadTexture(invaders_sprite_sheet)

	game := Game {
		last_tick = time.now(),
		pause = true,
		colors = []rl.Color{rl.BLACK, rl.WHITE},
		width = 64,
		height = 64,
		player = Player {
			sprite = PLAYER_SPRITE,
			rect =  {
				x = 200,
				y = 200,
				width = f32(PLAYER_SPRITE.width) * RESOLUTION_MULTIPLIER,
				height = f32(PLAYER_SPRITE.height) * RESOLUTION_MULTIPLIER,
			},
			num_lives = 3,
			velocity = 400,
			shooting_freq = 2,
		},
	}

	for i in 0 ..< NUM_ENEMIES {
		append(
			&game.enemies,
			Enemy {
				sprite = SIMPLE_ENEMY_SPRITE,
				rect = rl.Rectangle {
					x = (f32(i) * 100) + 50,
					y = 100,
					width = SIMPLE_ENEMY_SPRITE.width * RESOLUTION_MULTIPLIER,
					height = SIMPLE_ENEMY_SPRITE.height *
					RESOLUTION_MULTIPLIER,
				},
				health = 10,
				velocity = 400,
			},
		)

	}

	rl.SetMusicVolume(music, 0.1)
	rl.PlayMusicStream(music)

	// Infinite game loop. Breaks on pressing <Esc>
	for !rl.WindowShouldClose() {
		// all the valeus in game used to be separate variables and were
		// moved into a single Game struct. `using game` is a quick fix
		// to get the program back to running. Comment this line to see
		// where the variables were used and updated.
		using game

		rl.UpdateMusicStream(music)
		// If the user resized the window, we adjust the cell size to keep drawing over the entire window.
		if rl.IsWindowResized() {
			window.width = rl.GetScreenWidth()
			window.height = rl.GetScreenHeight()
		}

		// Step 1: process user input
		// First the user input gets translated into meaningful attribute names
		// Then we use those to taken action based on them.
		process_user_input(&user_input, window)

		if user_input.left_mouse_clicked {
			//fmt.println("left mouse clicked")
		}
		if user_input.right_mouse_clicked {
			//fmt.println("right mouse clicked")
		}
		if user_input.toggle_pause {
			pause = !pause
		}

		if !game.lost && !game.won {
			update_game(
				&game,
				shoot_sound,
				invader_killed_sound,
				explosion_sound,
			)
		}

		// Step 3: Draw the world
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{0, 0, 0, 255})
		draw_player(
			game.player,
			invaders_sprite_sheet,
			game.player.sprite,
			rl.Vector2{0, 0},
			0,
		)

		for &bullet in game.player_bullets {
			switch bullet.state {
			case .NORMAL:
				draw_bullet(
					bullet,
					invaders_sprite_sheet,
					BULLET_SPRITE,
					rl.Vector2{0, 0},
					0,
				)
			case .SMALL_EXPLOSION:
				draw_bullet(
					bullet,
					invaders_sprite_sheet,
					BULLET_SMALL_EXPLOSION_SPRITE,
					rl.Vector2{0, 0},
					0,
				)
			case .LARGE_EXPLOSION:
				draw_bullet(
					bullet,
					invaders_sprite_sheet,
					BULLET_LARGE_EXPLOSION_SPRITE,
					rl.Vector2{0, 0},
					0,
				)
			}
		}

		for &enemy in game.enemies {
			draw_enemy(
				enemy,
				invaders_sprite_sheet,
				SIMPLE_ENEMY_SPRITE,
				rl.Vector2{0, 0},
				0,
			)
		}

		rl.DrawText(
			"(c) Marsh Island Game Studios",
			SCREEN_WIDTH - 350,
			SCREEN_HEIGHT - 30,
			20,
			rl.GRAY,
		)

		// TODO(Thomas): Cleanup, this is trash
		if game.won {
			rl.ClearBackground(rl.Color{0, 0, 0, 255})
			game.player.rect.x = SCREEN_WIDTH / 2
			game.player.rect.y = SCREEN_HEIGHT - 200
			draw_player(
				game.player,
				invaders_sprite_sheet,
				game.player.sprite,
				rl.Vector2{0, 0},
				0,
			)

			rl.DrawText(
				"YOU WON!!!",
				SCREEN_WIDTH / 2 - 200,
				SCREEN_HEIGHT / 2,
				40,
				rl.GRAY,
			)

			rl.DrawText(
				"(c) Marsh Island Game Studios",
				SCREEN_WIDTH - 350,
				SCREEN_HEIGHT - 30,
				20,
				rl.GRAY,
			)
		} else if game.lost {
			rl.ClearBackground(rl.Color{0, 0, 0, 255})
			game.player.rect.x = SCREEN_WIDTH / 2
			game.player.rect.y = SCREEN_HEIGHT - 200
			draw_player(
				game.player,
				invaders_sprite_sheet,
				game.player.sprite,
				rl.Vector2{0, 0},
				0,
			)

			rl.DrawText(
				"YOU LOST!!! BUHU CRY BABY",
				SCREEN_WIDTH / 2 - 250,
				SCREEN_HEIGHT / 2,
				40,
				rl.GRAY,
			)

			rl.DrawText(
				"(c) Marsh Island Game Studios",
				SCREEN_WIDTH - 350,
				SCREEN_HEIGHT - 30,
				20,
				rl.GRAY,
			)
		}

		rl.EndDrawing()
	}
}
