# Buddy Bots for L4D2 / gxLdBot Development Notes

Current branch: **0.7.0 player mode**. Building on the 0.6 guardian layer, this
branch makes the default bot posture more like another active L4D2 player: bots
can push map flow earlier, hold wider-but-bounded spacing, idle with more visible
impatience, and still snap back to the same rescue/defense guardrails when the
team is threatened. The older 0.6.3 escort feel is still available as
`escort` mode.

Small L4D2 VScript prototype exploring **more useful, more player-feeling
survivor bots**. The original goal was believability; the newer branches
deliberately spend more of the budget on bots that feel like active teammates,
not just a safer escort shell around the human.

This is still a prototype. It favors **observability over cleverness**: almost
every decision logs a reason so you can see *why* a bot did something before you
trust it to do more.

## Design Philosophy

"More human" pulls in two directions. We are deliberately building one of them:

- **A — more believable teammate** (what we build): callouts, positioning
  habits, hesitation, personality, looking after low players.
- **B — more fallible like a real player** (mostly deferred): misses, tunnel
  vision, panic. The non-controversial slices of B (hesitation, composure) are
  in; deliberate mistakes are *not*, and stay behind flags if ever added.

Both are separate from the common "improved bot" goal of just making bots
stronger. We spend the believability budget on what VScript can fully control —
**decisions, timing, target selection, vocalization, positioning, resource
choices** — and we are honest about the expensive low-yield corner:

> L4D2 bot **aiming and movement are engine-controlled**. VScript can nudge them
> with cvars / NetProps but cannot author them frame-by-frame. So "human-like
> aim/strafing" is the *last* thing we'd attempt, not the first.

Rule of thumb from the requirements doc still holds: **randomize timing and
style, not basic survival responsibility.**

## What's Implemented (features 1–10)

Each feature notes what is **enacted** (the game actually does it) vs **decided**
(we compute + log the intent; physically forcing it is a roadmap item that needs
force-button / NetProps work).

| # | Feature | Module | Enacted now | Decision API ready (not yet consumed) |
| - | --- | --- | --- | --- |
| 1 | **Callouts** | `social.nut` | Bots speak warnings on real events (Hunter/Smoker/Jockey/Charger pin, Tank/Witch spawn, teammate down, healing) via `SpeakResponseConcept`. Claims dedupe so only one bot calls out a given threat | speaker = nearest bot to victim |
| 2 | **Spatial roles / combat nudges** | `squad.nut` | Balanced point/anchor/flanker/follower per round; team spacing cvars nudged to squad average; nearby infected can receive a lightweight bot attack command | per-bot follow distance & lead bias stored (true per-bot spacing needs force-button) |
| 3 | **Focus / attention** | `squad.nut` | focus target + commitment time tracked and printable | `ShouldSwitchFocus` switch-cost model — **ready, consumed once the M2 rescue behavior lands** |
| 4 | **Claims** | `squad.nut` | shared reservation table with expiry; **consumed by callouts today**; ready for rescue/item arbitration | — |
| 5 | **Composure / stress** | `survival.nut` | per-bot composure computed live from nearby specials + pinned teammates; printable | `ReactionScale` multiplier — **ready, consumed once a delayed-reaction behavior exists (M2)** |
| 6 | **Resource style** | `survival.nut` | heal-intent rising edge drives a heal callout | personality heal threshold + `ShouldYieldItem` — ready, consumed once pickup logic lands |
| 7 | **Idle interaction** | `social.nut` | on a calm stall, point/flanker and very impatient bots can drift toward / face the lagging human; speech is intentionally not forced | lowest-priority fallback intent |
| 8 | **Bot cards** | `cards.nut` | per-bot roguelike card modifies role distance, lead pressure, assist timing, retreat threshold, composure, and reaction style; cards can reroll after 5 minutes | future cards can touch item/throwable economy once those actions exist |
| 9 | **Chat event hints / multiplayer guard** | `main.nut` | single-player chat can show card/action triggers; more than one human player makes gxLdBot sleep and restore cvars | `!hbot_chat` and `!hbot_mpguard` toggle these helpers |
| 10 | **Behavior modes** | `main.nut`, `squad.nut`, `social.nut` | `player` is default; `escort` restores old 0.6.3-style tuning; `safe` is conservative. Modes retune lead distance, max separation, progress pressure, idle thresholds, and personality spread | future modes can retune item/throwable behavior once those actions exist |

> **Honest status (updated for 0.3):** features 1, 4, 5, 7 are visible in-game.
> As of 0.3 the previously caller-less decision APIs are now **consumed by the
> action arbiter**: `ReactionScale` + composure can time the experimental rescue
> delay, `focus` and `claims` arbitrate rescue/cover ownership, and
> rescue/retreat/cover/idle are physically enacted when their flags are on.
> `ShouldYieldItem` and item-pickup remain decision-only (deferred — see the
> roadmap).
> In 0.6, the scripted rescue part remains implemented but is **off by default**;
> vanilla rescue is the normal pin-response path.

## 0.6 Cardbuild Hard-Carry Layer (Action Arbiter)

`actions.nut` adds a **single action arbiter** — the *only* place allowed to issue
`CommandABot` / forced buttons to a bot. It runs on its own ~0.18s think entity
(crisper than the 1Hz planning loop) and, per bot, picks the one highest-priority
intent and enacts it; when nothing applies it hands the bot back to vanilla with
`BOT_CMD_RESET`. General combat still mostly stays vanilla, but 0.4 adds a narrow
**assist** action for close-horde cleanup: if a survivor has enough commons within
~420 units, a bot briefly attacks the nearest common for a short burst, then
resets.

Priority (high → low):

| Behavior | Trigger | Enacted via |
| --- | --- | --- |
| **rescue** | teammate pinned by a special | adjacent + shovable → **shove** (`m_afButtonForced`); else **focus-fire** the special (`CommandABot` attack) |
| **retreat** | self low HP **and** swarmed point-blank | `CommandABot` retreat, short burst, then reset (cooldown) |
| **cover** | teammate downed **and** someone already reviving | move a spare to a guard spot between victim and threat, then hold |
| **assist** | survivor has a close common swarm | short `CommandABot` attack burst against nearest common |
| **progress** | nav flow is available and the bot is allowed to lead | `CommandABot` move to a higher-flow nav area |
| **scout** | point/flanker, left saferoom, path clear | `CommandABot` move ahead (reuses the 0.2 gates) |
| **idle** | calm stall | move toward + face the lagging human; no forced speech |
| *none* | — | `BOT_CMD_RESET` → vanilla AI |

Key properties: only **one** bot commits per downed cover target (claims); every
dropped action **resets** so no stale command lingers; pinned/incapped/staggering/
reviving bots are never commanded. Scripted pinned-teammate rescue is
flag-gated and **off by default** (`EnableRescue = false`) because vanilla rescue
is reliable and less likely to fight the engine. All behaviors are flag-gated (`EnableRescue`,
`EnableRetreat`, `EnableCover`, `EnableShove`, `EnableAssist`, `EnableScout`,
`EnableProgress`, `EnableIdle`, master `EnableActions`). `!hbot_actions` prints
each bot's live action, and the toggle commands below can disable individual
behavior layers during testing.

**Deliberately not enacted:** forced self-heal (vanilla heals when safe; the
`FL_FROZEN` recipe is known but deferred), throwables, weapon-swap/pickup
economy, melee weapons, teleport-rescue (a non-human cheat), and any continuous
aim takeover (`SnapEyeAngles` is used only as a single nudge before a shove).
0.4 does use stronger aim/awareness cvars (`sb_combat_saccade_speed`,
`sb_normal_saccade_speed`, hearing/threat ranges, calm delays, all-bot play
cvars), but keeps direct combat scripting limited to the assist burst.

## Personality Profile

Each survivor bot gets a per-round profile. Roles set the broad squad job;
personal follow/lead offsets are mixed back in so bots keep visible differences.

| Field | Meaning |
| --- | --- |
| `role` | point / anchor / flanker / follower (assigned per round) |
| `reaction` | base reaction multiplier |
| `rescueBias` | priority weight for saving teammates |
| `followDistance` / `leadBias` | final spacing / lead habit after role + personality |
| `personalFollowOffset` / `personalLeadBias` | per-bot variance mixed into role assignment |
| `itemCuriosity` / `throwableBias` | item/grenade interest (for later behaviors) |
| `waitBias` | patience while the team stalls; low values take idle follow/facing actions sooner |
| `interactionBias` | playful/attention behavior weight (reserved) |
| `composureBase` | starting composure before threat pressure |
| `healThreshold` | HP at which this personality wants to heal |
| `letItemBias` | generosity — leave items for needier humans |

## Bot Cards

Cards are intentionally **modifiers, not command sources**. They change the
numbers that existing systems already read, then the action arbiter still makes
one final decision per bot. This keeps the roguelike layer expressive without
creating a second AI that fights movement/combat.

Default behavior:

- Cards are enabled by default (`cards=true` in `!hbot_status`).
- A bot gets one card when its profile/role is assigned.
- Every `300s`, each bot has a `22%` chance to reroll into a different card.
- `!hbot_reroll_cards` force-rerolls all current bot cards for testing.

Current card pool:

| Card | Flavor |
| --- | --- |
| Vanguard | pushes map flow hard and accepts wider spacing |
| Bodyguard | stays closer to the human and clears nearby pressure |
| Sweeper | turns close-horde assist on earlier and longer |
| Berserker | reacts fast and leads, but rarely backs off |
| Veteran | rare stable carry card |
| Rookie | slower and messier, but still useful |
| Skittish | stays close and retreats earlier |
| Ranger | mobile flanker with moderate forward pressure |

## Chat Hints And Multiplayer Guard

0.6.2 keeps a lightweight chat-hint layer for single-player testing, but action
spam is quiet by default. Card draws/rerolls and startup state can still appear
in chat; `action:*` hints only appear while `!hbot_debug` is enabled. Use
`!hbot_chat` to toggle the layer.

This mod is designed for single-player / local bot experiments. With
`mpGuard=true`, gxLdBot counts human players; if it sees more than one, it goes
to sleep, clears active bot commands, and restores cvars. This reduces risk in
multiplayer, but it cannot prevent crashes that happen earlier while L4D2 is
mounting or scanning addons during the loading screen. If joining a server still
crashes, temporarily move `gxldbot.vpk` out of `left4dead2/addons` to confirm
whether the VPK itself is involved.

## Behavior Modes

0.7 adds an explicit behavior-mode layer. The default is now `player`: bots are
allowed to behave more like another player in the run, not just a bodyguard.
They can push objective flow sooner, stand farther ahead when safe, show more
idle impatience around a stalled human, and vary their personal lead/item/idle
traits more strongly. The existing hard guardrails still win: pin/incap defense,
team stress, combat nearby, start-saferoom gates, and max-separation checks shut
down optional forward pressure.

Modes:

| Mode | Use |
| --- | --- |
| `player` | Default. More self-directed "buddy/pub teammate" behavior. |
| `escort` | Old 0.6.3-style behavior: tighter, more human-centered, less pushy. |
| `safe` | Conservative debug mode with shorter leads and quieter idle movement. |

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

Type in chat during a local / scripted game:

```text
!hbot_help        list commands
!hbot_status      version, mode, debug state, bot/human counts, cvar/scout/progress/action state
!hbot_mode        print current behavior mode and switch commands
!hbot_mode player
                  switch to the default player-like buddy mode
!hbot_mode escort
                  switch back to old 0.6.3-style escort behavior
!hbot_mode safe   switch to conservative debug behavior
!hbot_profile     print each bot's full profile
!hbot_roles       print assigned roles + spacing
!hbot_focus       print current focus target per bot
!hbot_claims      print active reservations
!hbot_actions     print each bot's current arbiter action (rescue/defend/retreat/cover/heal/escort/assist/progress/scout/idle)
!hbot_regen       regenerate profiles + roles
!hbot_debug       toggle verbose debug logging
!hbot_debugfile   toggle writing debug log to gxldbot/debug.txt
!hbot_chat        toggle single-player chat event hints
!hbot_mpguard     toggle multiplayer sleep guard
!hbot_cvars       toggle aggressive bot cvar tuning (on by default)
!hbot_scout       toggle point/flanker forward scouting
!hbot_progress    toggle flow-based auto-progress
!hbot_progress_status
                  print each bot's flow and target lead
!hbot_cards       print each bot's current card and reroll timer
!hbot_reroll_cards
                  force-reroll all current bot cards
!hbot_cards_toggle
                  toggle the card modifier layer
!hbot_actions_toggle
                  toggle the whole action arbiter
!hbot_rescue      toggle experimental scripted rescue (off by default; vanilla rescue is normal)
!hbot_retreat     toggle low-health swarm retreat
!hbot_cover       toggle downed-teammate cover behavior
!hbot_shove       toggle forced shove during rescue
!hbot_assist      toggle close-horde attack assist
```

From the developer console, use `scripted_user_func` instead of typing the bang
command directly:

```text
scripted_user_func hbot_status
scripted_user_func hbot_mode_player
scripted_user_func hbot_mode_escort
scripted_user_func hbot_mode_safe
scripted_user_func hbot_profile
scripted_user_func hbot_roles
scripted_user_func hbot_debug
scripted_user_func hbot_chat
scripted_user_func hbot_mpguard
scripted_user_func hbot_cvars
scripted_user_func hbot_scout
scripted_user_func hbot_progress
scripted_user_func hbot_progress_status
scripted_user_func hbot_cards
scripted_user_func hbot_reroll_cards
scripted_user_func hbot_cards_toggle
scripted_user_func hbot_actions
scripted_user_func hbot_actions_toggle
scripted_user_func hbot_rescue
scripted_user_func hbot_retreat
scripted_user_func hbot_cover
scripted_user_func hbot_shove
scripted_user_func hbot_assist
```

Typing `!hbot_status` directly at the `]` console prompt is expected to print
`Unknown command`; that prompt only runs Source console commands.

## Architecture

```text
addoninfo.txt
scripts/vscripts/director_base_addon.nut   entry; includes gxldbot/main
scripts/vscripts/gxldbot/main.nut          core: state, profiles, think loop,
                                            commands, chat hints, mp guard,
                                            hook registries, includes
scripts/vscripts/gxldbot/squad.nut         roles (#2), focus (#3), claims (#4),
                                            ScoutIntentFor
scripts/vscripts/gxldbot/survival.nut      composure (#5), resource style (#6),
                                            ShouldRetreat
scripts/vscripts/gxldbot/social.nut        callouts (#1), idle intent (#7)
scripts/vscripts/gxldbot/progress.nut      flow-based autonomous map advancement
scripts/vscripts/gxldbot/cards.nut         roguelike per-bot card modifiers
scripts/vscripts/gxldbot/actions.nut       action arbiter: enact primitives,
                                            rescue/retreat/cover/assist/progress/scout/idle
```

## Build / Install Locally

Close L4D2 before overwriting the installed VPK. The game keeps addon VPKs open
while running.

PowerShell:

```powershell
& "F:\SteamLibrary\steamapps\common\Left 4 Dead 2\bin\vpk.exe" "E:\diff\l4d2-mod-inspect\gxLdBot"
Copy-Item -LiteralPath "E:\diff\l4d2-mod-inspect\gxldbot.vpk" -Destination "F:\SteamLibrary\steamapps\common\Left 4 Dead 2\left4dead2\addons\gxldbot.vpk" -Force
```

Explorer shortcut: drag the whole `gxLdBot` folder onto `vpk.exe`, then copy the
generated `gxldbot.vpk` into `left4dead2\addons`.

Core wiring:

- **Hook registries.** Modules call `RegisterThink(name, fn)` and
  `RegisterRound(name, fn)` at include time. The think loop and round-start run
  every hook inside `SafeCall`, so one module throwing can't stop the others or
  kill the loop (fail-closed, per the requirements).
- **State tables.** `Profiles`, `Focus`, `Composure`, `Claims`, `LastSpeak` —
  all keyed by entity index and cleared on round start.
- **One think entity** (`info_target` + `AddThinkToEnt`) at 1 Hz drives
  everything; no per-frame scanning.
- **Load order.** `main` defines core, then includes `cards` → `squad` →
  `survival` → `social` → `progress` → `actions`, then collects events.
  Cross-module calls (e.g. focus reading composure) happen at *runtime*, so
  include order is safe.

## Fixes applied

From review of the 0.1 skeleton:

1. **Chat output** uses `ClientPrint(player, 5, "\x04…\x01…")` — L4D2 chat is
   message **type 5** with a color byte. (Was type 3, which silently shows
   nothing.)
2. **`IsValidEntity`** fails **closed** (returns false on exception).
3. **`RoundStart`** debounces so `round_start` and `round_start_post_nav` don't
   double-initialize. `LastRoundInit` starts at `-999` so the **first** round
   (when `Time()` may be < 1.0) is never skipped.

From the second review:

4. **Late-spawning bots get roles.** `EnsureProfiles` re-runs `AssignRoles`
   whenever a new bot profile appears (late spawn, takeover, `!hbot_regen`), not
   just at round start — so nobody is stuck on the default `follower`.
5. **`!hbot_cvars` off restores cvars.** Originals are snapshotted via
   `TrackedSetCvar` and put back by `RestoreMildCvars`, so toggling off actually
   reverts game behavior instead of leaving stale values with the UI saying
   "off". Squad spacing cvars go through the same backup.
6. **`Speak()` has a fallback.** Tries `EntFireByHandle`, then the older
   `DoEntFire("!self", …, bot)` form VSLib uses, so callouts don't vanish if one
   global is unavailable.
7. **`HasMedkit` uses `GetInvTable` + `slot3`** (the reference mod's method),
   survivor-guarded because `GetInvTable` crashes on a non-survivor/null. (Was a
   raw `m_hMyWeapons[3]` index guess.)

From the aggressive-experiment (0.2.1) review — fixing three field-reported bugs:

8. **Bots no longer bolt the start saferoom.** Forward pressure is now gated on
   `Director.HasAnySurvivorLeftSafeArea()` (plus a per-bot `m_isInMissionStartArea`
   guard): `ScoutTick` issues no move orders, and `sb_allow_leading` is held at
   `0`, until the human actually leaves. `sb_allow_leading` is therefore managed
   dynamically by `UpdateDynamicCvars` each think instead of being force-enabled
   in `ApplyMildCvars` / `ApplyTeamSpacing`.
9. **Bots fight back when surrounded.** The old scout logic only *skipped* the
   next move order near a threat; the stale `CommandABot` move command kept the
   bot walking into the horde. In 0.3, scout is only an intent consumed by the
   arbiter; any dropped action issues `BOT_CMD_RESET` (`cmd = 3`) once and hands
   control back to the engine's combat AI. General combat nudges were removed so
   commons and unpinning specials stay vanilla.
10. **Less scatter / isolation.** `MaxSeparation` 1900 → 900, role follow
    distances pulled in (point 760 → 520, flanker 620 → 440, …),
    `ScoutAheadDistance` 760 → 400, `sb_path_lookahead_range` 5000 → 3000 so bots
    stay close enough to support each other instead of straggling out alone.
11. **0.3.1 review fixes.** Action disable clears active actions and shove bits;
    revive state is tracked from `revive_begin/end/success` instead of guessed by
    proximity; CVar restore uses `gxldbot/cvars.txt` to persist the first clean
    values across map transitions, with a static fallback table; saferoom fallback
    is fail-closed; `GetInvTable` is guarded by an alive-survivor check; and
    action kind changes release old claims before taking over.
12. **0.3.2 actions load hardening.** Action module state is initialized by
    `main.nut`, so `actions.nut` has no top-level state slots that can fail
    during hot reload. `!hbot_actions` now retries `IncludeScript("gxldbot/actions")`
    and logs the include error if the module still cannot load.
13. **0.3.3 Squirrel syntax fix.** Renamed the rescue-delay local variable from
    reserved word `base` to `delayBase`; L4D2's Squirrel parser rejects `base`
    as an identifier and prevented `gxldbot/actions` from loading.
14. **0.4.0 hard-carry tuning.** Pulls from `Improved Bots (Advanced)` and
    `Advanced Bot AI - Custom`: all-bot play cvars, much faster saccade speeds,
    wider threat/hearing ranges, zero calm delays, faster rescue, more assertive
    point/flanker spacing, less retreating, and a narrow close-horde `assist`
    action for common-infected cleanup.
15. **0.4.1 escort correction.** Pulls the squad back around the human: tighter
    role distances, lower max separation/proximity range, shorter scout offset,
    movement observation based on human motion when humans exist, and idle no
    longer speaks `PlayerWaitHere`.
16. **0.5.0 auto-progress.** Adds `gxldbot/progress.nut`: bots can choose
    higher-flow nav areas via `GetFlowDistanceForPosition` and
    `NavMesh.GetNavAreasInRadius`, so forward movement is based on map flow
    rather than the human's view direction.
17. **0.5.1 progress fix.** Unifies version metadata; `!hbot_status` reports
    `progress`; flow movement appears as `action=progress`; personality lead /
    follow offsets survive role assignment; and all-bot tests are no longer
    blocked by the human saferoom gate.
18. **0.6.0 cardbuild.** Adds `gxldbot/cards.nut`: every bot gets a high-variance
    roguelike card that modifies existing role/progress/assist/retreat surfaces;
    cards can reroll every 5 minutes at a low chance. Scripted rescue is now
    off by default so vanilla rescue handles pins, while bot strength is raised
    through faster vanilla rescue cvars, stronger flow lead, and earlier
    close-horde assist.
19. **0.6.1 chatguard.** Adds single-player chat event hints for card/action
    triggers, plus a multiplayer sleep guard that clears active commands and
    restores cvars when more than one human player is detected.
20. **0.6.2 escort.** Tightens roles and cvars around the human, adds an
    `escort` catch-up action before optional assist/progress, reduces card lead
    and separation bonuses, quiets action chat by default, and makes close-horde
    assist trigger earlier near the player.
21. **0.6.3 guardian.** Adds emergency defend behavior for pinned/incapped
    humans, doubles emergency assist/detection pressure, makes assist target
    nearby Witch/specials before commons, gives stalled teams a short flow-based
    advance boost, and adds idle micro-movement around the human.
22. **0.7.0 player mode.** Adds a behavior-mode layer. `player` is now the
    default and makes bots more self-directed: wider-but-bounded spacing,
    earlier flow pushes, more lead-biased roles, and more visible idle
    impatience. `escort` preserves the old 0.6.3-style human-centered behavior,
    and `safe` provides a quieter conservative debug profile.

## Verified against working code

These were confirmed by grepping the shipped `Advanced Bot AI - Custom` /
VSLib, not assumed:

- `IsPlayerABot()`, `function Table::method()` syntax, `__CollectEventCallbacks`
- `SpeakResponseConcept` via EntFire, pin NetProps (`m_tongueOwner`,
  `m_pounceAttacker`, `m_jockeyAttacker`, `m_carryAttacker`, `m_pummelAttacker`)
- `FindByClassnameWithin`, `GetPropEntityArray`, `GetHealthBuffer`,
  `GetActiveWeapon`
- `GetFlowDistanceForPosition`, `NavMesh.GetNavAreasInRadius`, `area.GetCenter`
- every `sb_*` cvar name against `Improved Bots/scripts/gamemodes.txt`

**Two globals to confirm on first real run** (already wrapped in try/catch, so
they degrade instead of crashing):

- `GetPlayerFromUserID` — used to resolve chat/event players. If absent,
  callouts that key off a victim fall back to a generic speaker, and command
  echo broadcasts to everyone.
- `EntFireByHandle` — used for `Speak`. If absent, swap to
  `DoEntFire("!self", "SpeakResponseConcept", concept, 0, null, bot)` (the older
  style the reference mod uses).

## Testing Notes

- **Disable `Advanced Bot AI - Custom` while testing gxLdBot.** Both claim
  `director_base_addon.nut`; only one entry point wins. With both enabled you
  may think gxLdBot didn't load.
- Quick smoke test: load a map, `!hbot_status` should print `v0.7.0-player`,
  `mode=player`, `sleep=false`, `chat=true`, `mpGuard=true`, `cards=true`,
  `rescue=false`;
  `!hbot_cards` should show one card per bot and a reroll timer; `!hbot_roles`
  should show roles plus card names.
- Aggressive cvars, cards, progress/scouting, and the action arbiter are **on by
  default**; use `!hbot_cvars`, `!hbot_cards_toggle`, `!hbot_progress`,
  `!hbot_scout`, `!hbot_actions_toggle`, `!hbot_retreat`, `!hbot_cover`,
  `!hbot_shove`, or `!hbot_assist` to disable layers, and `!hbot_actions` /
  `!hbot_progress_status` / `!hbot_cards` to see what the arbiter/card layer is
  doing during comparison testing.
- Behavior checks: get pinned by a Hunter → vanilla rescue should respond
  quickly without `action=rescue` unless you manually enable `!hbot_rescue`; go
  down → a spare bot moves to cover once someone starts reviving; no bot should
  freeze on a stale command (a statue = a missing reset, the key regression to
  watch).
- Multiplayer check: in a session with another human, `!hbot_status` should show
  `sleep=true`; gxLdBot should not issue action commands or keep its cvars
  applied. Loading-screen crashes still require the manual VPK isolation test
  above because the script may not run before the crash.

## Roadmap

The action arbiter can enact rescue, shove, retreat, cover, assist, progress,
scout, and idle approach, but scripted rescue is disabled by default in 0.6.
Remaining enactment ideas:

- Press heal when heal-intent fires (`FL_FROZEN` + equip medkit + force attack;
  recipe known, deferred since vanilla self-heals when safe).
- Per-bot spacing instead of team-average cvars (needs continuous force-button
  movement, heavier than the current move commands).
- Throwables (pipe/molotov) once a safe equip→aim→throw sequence is proven.

Deferred on purpose: full combat AI takeover, weapon-swap economy, melee
weapons, teleport-rescue (a non-human cheat), aim-error injection, and any
deliberate-mistake (direction B) behaviors.

## Review Focus

- Are the callout **concept strings** the right ones for survivor warnings?
  (`PlayerWarnHunter` etc. — easy to expand once confirmed in-game.)
- Is `GetInvTable` available in the target mode, and is `slot3` always the
  medkit slot? (`HasMedkit` is alive-survivor guarded against the known crash,
  but the slot key should be confirmed in-game.)
- Should commands be **host/admin only**? (Currently anyone; documented, low
  priority for a prototype.)
- Are composure / focus tuning constants in a sensible range?
- **0.3 enactment:** the primitives (`CommandABot` move/attack/retreat/reset,
  `m_afButtonForced` shove with `m_iShovePenalty`/`m_flNextSecondaryAttack`
  reset, `SnapEyeAngles`, pin NetProps) are all copied from the shipped Advanced
  Bot AI mod, but confirm in-game that shoves actually break a pin in the target
  mode and that the arbiter's reset reliably returns bots to vanilla combat.
