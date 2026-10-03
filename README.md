# Shadow City

An original, procedural third-person stealth-action prototype for **Godot 4.3**. The playable city is assembled from primitive meshes at runtime, so no external art assets are required.

## Run

Open `project.godot` in Godot 4.3 and run the project. The entry scene is `scenes/main.tscn`.

## Controls

| Input | Action |
| --- | --- |
| `W` / `A` / `S` / `D` | Camera-relative movement |
| `Shift` | Sprint |
| `Space` | Jump |
| Mouse | Orbit the offset spring-arm third-person camera |
| `E` | Interact with the nearby current-objective device |
| `R` | Restart the prototype |
| `Esc` | Pause or resume the mission |

## Systems in this milestone

- **Larger procedural city:** A 140×140 district contains a five-by-five street grid, sixteen varied blocks (towers, courtyards, warehouses, and slab complexes), street lighting, a market, transit signage, and a skyline uplink.
- **Playable pedestrian space:** Eight civilians walk distinct sidewalk loops, turn toward their travel direction, and briefly pause at corners. Four guards patrol separate sectors.
- **Improved movement and camera:** Camera-relative movement has responsive acceleration/deceleration, coyote-time jumping, sprint FOV feedback, smooth visual turning, and an offset spring arm that avoids building clipping.
- **More responsive city life:** Guards investigate the player’s last seen position after a detection, while civilians step away when the player crowds them before returning to their routes.
- **Expanded mission route:** Complete six sequential objectives: gate, access chip, two relays, survey-data uplink, and extraction beacon. The HUD exposes only the valid interaction, displays its distance, and highlights the usable device.
- **Pause menu:** `Esc` freezes the simulation and opens a focused pause overlay; resume with `Esc` or restart the district with `R`.

## Project layout

- `scenes/main.tscn` is the small entry scene.
- `scripts/shadow_city.gd` creates the playable city, HUD, interaction objects, guards/civilians, camera, and player controller.
