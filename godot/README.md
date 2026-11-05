# Crimson Red 3D: Godot project

Open with `../play_sandbox` (the sandbox battle), `../view_model` (character/gear viewer) or `../view_stage` (the dungeon). Checks: `../test_3d`.

| Folder | What lives there |
|---|---|
| `sim/` | The headless simulation, no nodes: `nav_grid` (walkable area + A*), `orca` (avoidance), `steer_world` (the movement stack), `slots` (melee engagement positions), `sandbox_battle` (a toy combat on top of them), `game_data` (exported data + px->m conversions). |
| `ui/` | `SmoothValue`, `SmoothVec2`, `SmoothRect`, `SmoothColor`: every gradual UI change. |
| `view/` | Presentation: `stage_scene` (stage, lights, dimetric camera, ground picking), `unit_view` (rig + gear + clips driven from the sim), `picking` (which unit is under the mouse), `sandbox_battle_view` (the playable sandbox: input, HUD, debug overlay). |
| `data/` | `*.json` exported from the 2D game by `../export_data` (generated; never edit) and the hand-authored tables (`unit_sizes.json`, `items_catalog.json`, `rewards.json`, tiers). |
| `models/` | Characters, gear (`gear/`) and the stage (`stage/`), built by `../blender/*.py` and `../build_model`. |
| `tests/` | Headless checks: `smooth_value_test`, `data_test`, `steering_lab`, `sandbox_test`, `sandbox_view_test`, `picking_test`. |

GDScript only. `sim/` uses `preload` constants instead of `class_name` so it runs under `--script` without the editor's class cache.
