# Buddy Bots for L4D2

[中文说明](README.zh-CN.md)

Buddy Bots for L4D2 is a small Left 4 Dead 2 VScript addon prototype that makes
survivor bots feel more like active teammates instead of passive escorts.

The internal script namespace is still `gxLdBot`; the public project name is
Buddy Bots for L4D2.

## Status

Current version: `0.7.1-strength`

This is experimental. It is built for single-player and local bot testing first.
It does not replace the Source engine survivor AI. It nudges vanilla bot
behavior through VScript, cvars, event callbacks, `CommandABot`, and guarded
NetProps usage.

## Design Goal

The main goal is not "stronger bots at any cost." The goal is bots that feel
more like another player in the run:

- they may push forward when the route is clear;
- they may show impatience when the team stalls;
- they have varied roles, personalities, and cards;
- they still snap back to rescue and defense when someone is pinned, downed, or
  under pressure.

Rule of thumb: randomize timing and style, not basic survival responsibility.

## Features

- Player-like default behavior mode with wider-but-bounded forward pressure.
- Old escort-style mode for the previous tighter, human-centered behavior.
- Conservative safe mode for debugging.
- Per-bot roles: point, flanker, follower, anchor.
- Per-bot personality profiles and roguelike-style bot cards.
- Flow-based map advancement using nav flow when available.
- Single action arbiter for move, attack, shove, retreat, cover, assist,
  progress, scout, idle, and optional scripted rescue actions.
- Emergency defense for pinned or incapacitated humans.
- Callouts for pins, Tank/Witch spawns, downs, and heal intent.
- Multiplayer guard that sleeps and restores cvars when more than one human is
  detected.
- Chat and console debug commands.

## Behavior Modes

`player` is the default. It is the "active teammate" mode.

| Mode | Use |
| --- | --- |
| `player` | Default. More self-directed buddy/pub teammate behavior. |
| `escort` | Old 0.6.3-style behavior: tighter, more human-centered, less pushy. |
| `safe` | Conservative debug behavior with shorter leads and quieter idle movement. |

Switch in chat:

```text
!hbot_mode player
!hbot_mode escort
!hbot_mode safe
```

Switch from the developer console:

```text
scripted_user_func hbot_mode_player
scripted_user_func hbot_mode_escort
scripted_user_func hbot_mode_safe
```

## Commands

Chat commands work in a local/scripted game:

```text
!hbot_help
!hbot_status
!hbot_mode
!hbot_profile
!hbot_roles
!hbot_actions
!hbot_progress_status
!hbot_cards
!hbot_debug
!hbot_debugfile
!hbot_chat
!hbot_mpguard
!hbot_cvars
!hbot_scout
!hbot_progress
!hbot_actions_toggle
!hbot_rescue
!hbot_retreat
!hbot_cover
!hbot_shove
!hbot_assist
```

From the console, use `scripted_user_func`:

```text
scripted_user_func hbot_status
scripted_user_func hbot_mode_player
scripted_user_func hbot_mode_escort
scripted_user_func hbot_mode_safe
scripted_user_func hbot_actions
scripted_user_func hbot_progress_status
scripted_user_func hbot_cards
```

Typing `!hbot_status` directly at the `]` console prompt is expected to fail;
that prompt only runs Source console commands.

## Build

Close L4D2 before overwriting an installed VPK. The game keeps addon VPK files
open while running.

Build only:

```powershell
.\build-vpk.ps1
```

Build and install to the default L4D2 path:

```powershell
.\build-vpk.ps1 -Install
```

Custom paths:

```powershell
.\build-vpk.ps1 -VpkExe "F:\SteamLibrary\steamapps\common\Left 4 Dead 2\bin\vpk.exe"
.\build-vpk.ps1 -L4D2Path "F:\SteamLibrary\steamapps\common\Left 4 Dead 2" -Install
```

The generated file is `gxldbot.vpk`.

## Install Manually

Copy `gxldbot.vpk` into:

```text
Left 4 Dead 2/left4dead2/addons/gxldbot.vpk
```

Then restart L4D2 or reload the map.

## Quick Smoke Test

1. Disable other script addons that also ship `director_base_addon.nut`.
2. Start a local map, for example `c1m1_hotel`.
3. Run `scripted_user_func hbot_status`.
4. Expected status includes `v0.7.1-strength`, `mode=player`, `cards=true`,
   `progress=true`, `actions=true`, and `rescue=false`.
5. Run `scripted_user_func hbot_mode_escort` to confirm old-style mode switching.

## Repository Layout

```text
gxLdBot/
  addoninfo.txt
  scripts/vscripts/director_base_addon.nut
  scripts/vscripts/gxldbot/*.nut
build-vpk.ps1
requirements.md
bot-ai-comparison.md
```

`gxLdBot/README.md` is the longer development notebook. The root README is the
public-facing project overview.

## Known Limits

- Full aim and movement are still controlled by the engine.
- Flow-based progress depends on map/nav flow being available.
- Scripted rescue exists but is off by default; vanilla rescue is usually safer.
- Item pickup, throwable economy, weapon swaps, and full combat takeover are not
  the focus of this version.
- Multiplayer guard reduces risk, but loading-screen addon conflicts can happen
  before VScript gets a chance to sleep.

## Credits And Research Notes

The project was informed by local inspection of existing L4D2 bot addons and
Source/L4D2 VScript behavior. Reference addon folders are intentionally excluded
from this repository; only this addon source is meant to be published here.

## License

MIT. See [LICENSE](LICENSE).
