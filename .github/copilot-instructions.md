# SOF2 Mod - Copilot Instructions

## Project
Soldier of Fortune 2 Double Helix modding workspace.
Game engine: id Tech 3 (Quake 3 base) with Raven's Ghoul2 skeletal system.
Active mod folder: `WeaponMod\` - loaded via shortcut arg `+set fs_game WeaponMod`.

## Installation on a fresh machine

1. Install SOF2 to any folder
2. Clone this repo **into** that folder (must overlay the game files):
   ```
   git clone https://github.com/IP-Designs/sof2-mods "C:\path\to\Soldier of Fortune 2"
   ```
3. Download **PerfectFX 2.0** separately (not in repo - not ours to redistribute).
   Extract these 4 files into `base\`:
   - `XTK_PerfectFX2.0.pk3`
   - `XTK_PerfectFX2.0_Gore.pk3`
   - `XTK_PerfectFX2.0_MF_New.pk3`
   - `XTK_PerfectFX2.0_WM.pk3`
4. Edit the game shortcut Target field to end with:
   ```
   +set fs_game WeaponMod
   ```
5. Launch the game. All settings apply automatically via `autoexec.cfg`.

## Repo contents

| File | Purpose |
|---|---|
| `build_damage_mod.ps1` | Edit damage values at top, run to rebuild `zz_realistic_damage.pk3` |
| `base/autoexec.cfg` | Gore/FX CVARs applied at startup (no mod active) |
| `base/sof2sp.cfg` | Singleplayer config (game overwrites on exit) |
| `base/sof2_weapons.wpn` | Extracted original weapon script (reference only) |
| `base/commands_reference.cfg` | All known CVARs documented |
| `WeaponMod/autoexec.cfg` | CVARs applied when WeaponMod is active |
| `WeaponMod/zz_realistic_damage.pk3` | Built damage override (zz_ = loads last = wins) |

## Rebuilding the damage mod

Open `build_damage_mod.ps1`, edit numbers in the `$Damage` table, then:
```
powershell -ExecutionPolicy Bypass -File ".\build_damage_mod.ps1"
```

## Key technical facts

- Player HP = 100. For 2-shot kill: damage > 50. Headshot multiplier ~2x.
- `setrandom sv_cheats 1` - regular `set` is blocked by engine protection.
- pk3 files load alphabetically. `zz_` prefix = loads last = overrides everything.
- Weapon scripts: plain-text `.wpn` files inside pk3 under `ext_data/` path.
- Viewmodel position is NOT CVARs - SOF2 uses Ghoul2 bone attachment. Needs DLL patch.
- `mp_gore "yes"` must be set per attack mode in the weapon script to enable gore.
