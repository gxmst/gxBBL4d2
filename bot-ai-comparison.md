# L4D2 Bot AI Mod Comparison

## What These Mods Actually Do

Neither mod replaces the Source engine survivor bot AI in the deep engine sense. They run on top of the built-in AI.

`Improved Bots (Advanced)` is mostly a parameter and UI addon. It changes built-in bot cvars in `scripts/gamemodes.txt`, then exposes some menu/radial commands.

`Advanced Bot AI - Custom` is a VScript controller layer. It still uses the built-in bot movement/combat/nav systems, but it adds its own state table, task scheduler, event callbacks, chat commands, item logic, danger avoidance, force-button control, NetProps edits, and some cvar overrides.

## File Layout

| Mod | Local path | Main entry |
| --- | --- | --- |
| Advanced Bot AI - Custom | `E:/diff/l4d2-mod-inspect/Advanced Bot AI - Custom` | `scripts/vscripts/director_base_addon.nut` -> `AIUpdateHandler` |
| Improved Bots (Advanced) | `E:/diff/l4d2-mod-inspect/Improved Bots (Advanced)` | `scripts/gamemodes.txt`, `scripts/radialmenu.txt`, `resource/ui/*.res` |

Generated extraction summary:

`E:/diff/l4d2-mod-inspect/_extracted-params.json`

## Improved Bots (Advanced)

This old mod is straightforward. Its core behavior is repeated across `coop`, `realism`, `survival`, `versus`, and some mutation modes.

Main cvar groups:

| Area | Parameters | Effect |
| --- | --- | --- |
| All-bot play | `sb_all_bot_game 1`, `allow_all_bot_survivor_team 1` | Allows the game to continue with only bots. |
| Leadership | `sb_allow_leading 0` | Stops survivor bots from leading the team. |
| Friendly fire behavior | `sb_allow_shoot_through_survivors 0` | Avoids shooting through teammates. |
| Rescue reaction | `sb_friend_immobilized_reaction_time_* 0.001` | Makes bots react almost instantly to pinned teammates. |
| Spacing/follow | `sb_separation_range 150`, `sb_neighbor_range 200`, `sb_escort 1` | Keeps bots closer and more escort-like. |
| Threat ranges | `sb_threat_*_range`, `sb_close_threat_range` | Reclassifies threat distances so bots respond sooner/closer. |
| Hearing | `sb_near_hearing_range 1000`, `sb_far_hearing_range 2000` | Lets bots notice threats farther away. |
| Aim/look speed | `sb_combat_saccade_speed 2000` | Speeds up target switching/aim movement. |
| Navigation patience | `sb_locomotion_wait_threshold 2`, `sb_path_lookahead_range 1000` | Tunes path following and stuck-ish behavior. |
| Safe room | `sb_close_checkpoint_door_interval 0.25` | Bots close safe room doors quickly. |
| Realism/mutations | `sv_disable_glow_*`, `z_witch_always_kills`, `z_non_head_damage_factor_multiplier`, etc. | Mode-specific difficulty/gameplay behavior, not really AI. |

Assessment:

This mod is the classic "make vanilla bot tolerable" style. It is useful as a baseline and as a catalog of built-in cvars. It does not implement much decision-making. It makes the original AI faster, closer, less passive, and less likely to let pinned players die.

## Advanced Bot AI - Custom

This mod is much more ambitious. It creates a global `BotAI` table in `scripts/vscripts/aiupdatehandler.nut`, loads VSLib, registers event callbacks, and starts timers.

Main loaded modules:

| Module | Role |
| --- | --- |
| `aiupdatehandler.nut` | Main state, defaults, callbacks, init, settings save/load. |
| `ai_lib/ai_timers.nut` | Think timers and recurring task loops. |
| `ai_lib/ai_command.nut` | Chat/menu commands and setting mutation. |
| `ai_lib/ai_events.nut` | Game event hooks and chat triggers. |
| `ai_lib/ai_navigator.nut` | Script-level movement helper. |
| `ai_taskes/*.nut` | Concrete bot tasks. |
| `rayman1103_vslib/*` | VSLib helper library. |

Default behavior switches and thresholds:

| Area | Key defaults | Meaning |
| --- | --- | --- |
| Combat skill | `BotCombatSkill = 0`, `BotSkill11 = true`, `BotSkillNerf = true`, `BotSkillNerfLevel = 1` | Uses a custom "skill 11" mode, then intentionally nerfs it by default. |
| Aim/awareness | `Skill11AlertDuration = 1.5`, `Skill11ShareVisionTraceCacheDuration = 0.35`, `Skill11MeleeCommonAssistAngle = 0` | Adds short-lived awareness and shared-vision style caches. |
| Tank/Witch survival | `BotTankProtect = true`, `BotWitchProtect = true`, tank/witch speed/evade thresholds | Tries to avoid instant deaths and bad Tank/Witch interactions. |
| Bio/acid/fire protection | `FallProtect = true`, `FireProtect = false`, `AcidProtect = false`, `NonAliveProtect = false` | Fall protection is on; more intrusive damage protections are off by default. |
| Acid avoidance | `AcidZoneCoreRadius = 170`, `AcidZoneKeepoutRadius = 240`, safe search radius/counts | Tracks Spitter acid zones and searches for safe nav areas. |
| Resource behavior | `NeedGasFinding = true`, `UseUpgrades = true`, `PassingItems = true`, `Defibrillator = true`, `BackPack = true` | Bots can search/use resources beyond vanilla behavior. |
| Throwables | `NeedThrowMolotov = true`, `NeedThrowPipeBomb = true`, `BotActivelyGrenade = true` | Bots actively decide to throw items. |
| Follow/stuck | `FollowRange = 200`, `TeleportDistance = 1000`, `SaveTeleport = 9`, `UnStick = true` | Script assists follow behavior and uses teleport as escape hatch. |
| Melee | `Melee = true`, `MeleeLimit = 2`, `sb_max_team_melee_weapons` forced later | Controls how many bots can use melee. |
| Damage scaling | all damage multipliers default `1.0` | Can buff/nerf bot damage against common, specials, Tank, Witch, nonliving. |
| Completion behavior | `NeedBotAlive = true`, `BotCompleteLevel = false`, `TeleportToSaferoom = false` | Can keep bot team alive or force level-completion helpers. |

Registered task list:

| Task | Interval args | Purpose |
| --- | --- | --- |
| `searchEntity` | `0, 1.5, false, false` | Search/pick useful entities. |
| `transItem` | `1, 10, false, false` | Pass items to humans. |
| `transKit` | `1, 10, true, false` | Transfer first aid kits in last-strike cases. |
| `heal` | `2, 20, false, false` | Heal logic. |
| `checkToThrowGen` | `0, 10, true, true` | Molotov/vomit jar style throw decisions. |
| `checkToThrowBomb` | `0, 10, true, true` | Pipe bomb decisions. |
| `savePlayer` | `1, 5, true, true` | Free pinned teammates. |
| `searchBody` | `2, 10, true, true` | Defib dead survivors. |
| `doUpgrades` | `3, 10, true, true` | Use ammo upgrades. |
| `healInSafeRoom` | `3, 10, true, true` | Heal in saferoom. |
| `searchTrigger` | `4, 10, true, true` | Trigger/use map objectives. |
| `tryTraceGascan` | `5, 10, true, true` | Find scavenge gascans. |
| `tryTakeGascan` | `5, 10, true, true` | Pour/use gascans. |
| `hitinfected` | `0, 2, true, true` | Recurring combat target handling. |
| `updateFireState` | `0, 1, true, true` | Force/disable fire and item state. |
| `shoveInfected` | `0, 1, true, true` | Shove close threats and clear shove penalty. |
| `avoidDanger` | `0, 2, true, true` | Avoid dangerous ground/projectiles/Tank/Witch cases. |

Important cvars changed at runtime:

| Cvar | Custom behavior |
| --- | --- |
| `sb_allow_leading` | Controlled by `PathFinding`; default off. |
| `sb_max_team_melee_weapons` | Forced to `0` at round start, later managed by custom melee limit logic. |
| `sb_separation_range`, `sb_neighbor_range`, `sb_separation_danger_*`, `sb_max_battlestation_range_from_human` | Derived from `FollowRange`, with different values if script pathfinding is on. |
| `sb_unstick`, `sb_enforce_proximity_range` | Used by teleport/unstick behavior. |
| `sb_toughness_buffer`, `sb_temp_health_consider_factor`, `sb_follow_stress_factor`, `sb_locomotion_wait_threshold`, `sb_path_lookahead_range` | Overrides vanilla bot tolerance and follow behavior. |
| `sb_vomit_blind_time` | Set to `0`, meaning bots are not blinded by vomit. This is strong but less human-like. |
| `survivor_calm_*` | Tuned so bots return to usable state faster. |
| `sv_consistency` | Set to `0`, probably to avoid model/script consistency issues. |

Persistence:

Settings are saved to:

`advanced bot ai/settings.txt`

The save list includes combat skill, follow distance, teleport distance, throwables, gas finding, item passing, protections, damage multipliers, debug mode, language, and backpack behavior.

## Side-by-Side Judgment

| Question | Improved Bots | Advanced Bot AI - Custom |
| --- | --- | --- |
| Is it a full AI replacement? | No | No, but much closer to a high-level behavior layer |
| Main method | Static cvar overrides | VScript task scheduler + cvars + NetProps |
| Debuggability | Simple | Harder, because behavior depends on timers/events/state |
| Human-like potential | Low to medium | Medium, but current defaults include some non-human cheats/protections |
| Stability risk | Low | Medium/high |
| Good learning value | Good cvar reference | Very good architecture reference |
| Best use | Baseline vanilla improvement | Starting point for behavior experiments |

## Should We Build Our Own?

Not from scratch yet.

The better path is to make a small clean experimental addon that borrows the architecture ideas, not necessarily the code:

1. Start with a minimal VScript addon.
2. Add only one or two behaviors first:
   - teammate rescue prioritization,
   - better follow/spacing,
   - item passing,
   - danger avoidance.
3. Add debug visibility before adding cleverness:
   - chat debug command,
   - current task per bot,
   - reason for target choice,
   - stuck/teleport counter,
   - last known threat.
4. Avoid "superhuman" helpers by default:
   - no permanent vomit blindness removal,
   - no broad damage reduction,
   - no aggressive teleport except as a visible stuck recovery,
   - no omniscient item/threat knowledge unless we label it as such.

The custom addon here already solved a lot of engineering plumbing, but it is large and messy enough that modifying it directly would be painful. A clean prototype gives us control over the design goal: "more human and legible", not just "stronger".

## Proposed Research Direction

For our own mod, the first meaningful experiment should be an "intent and task blackboard":

| Bot state | Example |
| --- | --- |
| Current task | `rescue_pinned_teammate`, `hold_follow_position`, `avoid_acid`, `pass_medkit` |
| Reason | `Zoey is pounced`, `acid zone near path`, `human has no throwable` |
| Confidence/priority | numeric score |
| Expiry | short timeout so stale decisions disappear |
| Debug output | optional chat/HUD print |

This would make tuning much less miserable. The hardest part of bot work is not writing another `if`; it is knowing why the bot did what it did.

