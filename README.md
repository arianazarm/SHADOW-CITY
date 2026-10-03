# Shadow City

An original, procedural third-person stealth-action prototype for **Godot 4.3**. The playable city is assembled from primitive meshes at runtime, so no external art assets are required.

## Run

Open `project.godot` in Godot 4.3 and run the project. The entry scene is `scenes/main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| `W` / `A` / `S` / `D` | Move |
| Mouse | Orbit the spring-arm third-person camera |
| `E` | Interact with the nearby highlighted-purpose object |
| `R` | Restart the prototype |
| `Esc` | Release mouse capture |

## Systems in this milestone

- **Expanded procedural city:** A 96×96 district has a street grid, eight building blocks, market stalls, lamps, a transit landmark, and five ambient civilian placeholders.
- **Improved movement and camera:** Camera-relative movement accelerates smoothly, the player mesh turns toward motion, gravity and building collisions keep movement grounded, and a spring arm keeps the third-person camera from clipping through buildings.
- **Interaction and objectives:** Follow a four-step route: open the transit gate, activate the East and Market relays, then signal the extraction beacon. An on-screen `E` prompt only exposes the current mission action.
- **Patrol and detection:** Three procedural guard placeholders walk looping routes across separate city sectors. Their forward cones detect the player at close range and issue a throttled alert.

## Project layout

- `scenes/main.tscn` is the small entry scene.
- `scripts/shadow_city.gd` creates the playable city, HUD, interaction objects, guards/civilians, camera, and player controller.
