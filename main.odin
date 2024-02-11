package main

import "core:fmt"
import math "core:math"
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
	rect:          rl.Rectangle,
	num_lives:     i32,
	velocity:      f32,
	shooting_freq: f32,
}

Enemy :: struct {
	rect:   rl.Rectangle,
	health: i32,
}

Bullet :: struct {
	rect:     rl.Rectangle,
	damage:   i32,
	velocity: f32,
}

Game :: struct {
	last_tick:      time.Time,
	pause:          bool,
	colors:         []rl.Color,
	width:          i32,
	height:         i32,
	player:         Player,
	enemies:        [dynamic]Enemy,
	player_bullets: [dynamic]Bullet,
}

UserInput :: struct {
	left_mouse_clicked:  bool,
	right_mouse_clicked: bool,
	toggle_pause:        bool,
	mouse_pos:           [2]f32,
}

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 1024

RESOLUTION_MULTIPLIER :: 3

PLAYER_SPRITE_WIDTH :: 8
PLAYER_SPRITE_HEIGHT :: 7

BULLET_SPRITE_WIDTH :: 2
BULLET_SPRITE_HEIGHT :: 3

SIMPLE_ENEMY_SPRITE_WIDTH :: 6
SIMPLE_ENEMY_SPRITE_HEIGHT :: 8

NUM_ENEMIES :: 10
NS_PER_SEC :: 1_000_000_000
NS_PER_MS :: 1_000_000

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
last_shoot_time: i64 = 0
angle: f32 = 0.0

update_game :: proc(
	game: ^Game,
	player_shoot_sound: rl.Sound,
	invader_killed_sound: rl.Sound,
	explosion_sound: rl.Sound,
) {
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
		if f32(now._nsec - last_shoot_time) >
		   1_000_000_000 / game.player.shooting_freq {
			rl.PlaySound(player_shoot_sound)
			append(
				&game.player_bullets,
				Bullet {
					rect = rl.Rectangle {
						x = game.player.rect.x,
						y = game.player.rect.y,
						width = BULLET_SPRITE_WIDTH * RESOLUTION_MULTIPLIER,
						height = BULLET_SPRITE_HEIGHT * RESOLUTION_MULTIPLIER,
					},
					damage = 10,
					velocity = 20,
				},
			)
			last_shoot_time = now._nsec
		}
	}

	// Update bullets
	for &bullet, bullet_idx in game.player_bullets {
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
				rl.PlaySound(explosion_sound)
				enemy.health -= bullet.damage
				if (enemy.health <= 0) {
					rl.PlaySound(invader_killed_sound)
					unordered_remove(&game.enemies, enemy_idx)
				}

				unordered_remove(&game.player_bullets, bullet_idx)
			}
		}

		bullet.rect.y -= bullet.velocity
	}


	// Update enemies
	for &enemy in game.enemies {
		radius: f32 = 5.0
		enemy.rect.x += math.cos(angle) * radius
		enemy.rect.y += math.sin(angle) * radius
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
		"Space Invaders!",
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		60,
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

	player_sprite_src_start_x := 0
	player_sprite_src_start_y := 1
	player_sprite_source_rect := rl.Rectangle {
		f32(player_sprite_src_start_x),
		f32(player_sprite_src_start_y),
		f32(PLAYER_SPRITE_WIDTH),
		f32(PLAYER_SPRITE_HEIGHT),
	}
	player_sprite_dst_rect := rl.Rectangle {
		SCREEN_WIDTH / 2.0,
		SCREEN_HEIGHT / 2.0,
		f32(PLAYER_SPRITE_WIDTH),
		f32(PLAYER_SPRITE_HEIGHT),
	}
	player_sprite_origin := rl.Vector2{0, 0}

	bullet_sprite_src_start_x := 11
	bullet_sprite_src_start_y := 19
	bullet_sprite_source_rect := rl.Rectangle {
		f32(bullet_sprite_src_start_x),
		f32(bullet_sprite_src_start_y),
		f32(BULLET_SPRITE_WIDTH),
		f32(BULLET_SPRITE_HEIGHT),
	}
	bullet_sprite_dst_rect := rl.Rectangle {
		SCREEN_WIDTH / 2.0,
		SCREEN_HEIGHT / 2.0,
		f32(BULLET_SPRITE_WIDTH),
		f32(BULLET_SPRITE_HEIGHT),
	}
	bullet_sprite_origin := rl.Vector2{0, 0}

	simple_enemy_sprite_src_start_x := 33
	simple_enemy_sprite_src_start_y := 0
	simple_enemey_sprite_source_rect := rl.Rectangle {
		f32(simple_enemy_sprite_src_start_x),
		f32(simple_enemy_sprite_src_start_y),
		f32(SIMPLE_ENEMY_SPRITE_WIDTH),
		f32(SIMPLE_ENEMY_SPRITE_HEIGHT),
	}
	simple_enemy_sprite_dst_rect := rl.Rectangle {
		SCREEN_WIDTH / 2.0,
		SCREEN_HEIGHT / 2.0,
		f32(SIMPLE_ENEMY_SPRITE_WIDTH),
		f32(SIMPLE_ENEMY_SPRITE_HEIGHT),
	}
	simple_enemy_sprite_origin := rl.Vector2{0, 0}


	game := Game {
		last_tick = time.now(),
		pause = true,
		colors = []rl.Color{rl.BLACK, rl.WHITE},
		width = 64,
		height = 64,
		player = Player {
			rect =  {
				x = 200,
				y = 200,
				width = f32(PLAYER_SPRITE_WIDTH) * RESOLUTION_MULTIPLIER,
				height = f32(PLAYER_SPRITE_HEIGHT) * RESOLUTION_MULTIPLIER,
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
				rect = rl.Rectangle {
					x = (f32(i) * 100) + 50,
					y = 100,
					width = SIMPLE_ENEMY_SPRITE_WIDTH * RESOLUTION_MULTIPLIER,
					height = SIMPLE_ENEMY_SPRITE_HEIGHT *
					RESOLUTION_MULTIPLIER,
				},
				health = 10,
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

		update_game(&game, shoot_sound, invader_killed_sound, explosion_sound)

		// Step 3: Draw the world
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{0, 0, 0, 255})
		draw_player(
			game.player,
			invaders_sprite_sheet,
			player_sprite_source_rect,
			player_sprite_origin,
			0,
		)

		for &bullet in game.player_bullets {
			draw_bullet(
				bullet,
				invaders_sprite_sheet,
				bullet_sprite_source_rect,
				bullet_sprite_origin,
				0,
			)
		}

		for &enemy in game.enemies {
			draw_enemy(
				enemy,
				invaders_sprite_sheet,
				simple_enemey_sprite_source_rect,
				simple_enemy_sprite_origin,
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

		rl.EndDrawing()
	}
}
