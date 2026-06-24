# L4D2 Humanized Bot AI Prototype Requirements

## Project Goal

Build a small L4D2 addon prototype that makes survivor bots feel slightly more capable and more human, without turning them into overpowered scripted machines.

The addon should sit on top of vanilla bot AI. It should not try to replace the engine AI completely.

Core direction:

- Mild bot parameter improvement.
- Randomized human-like timing and personality differences.
- Better debug visibility.
- Careful crash risk control.
- Small behavior experiments first, not a full AI rewrite.

## Existing Reference Mods

Research directory:

`E:/diff/l4d2-mod-inspect`

Reference mods:

- `Advanced Bot AI - Custom`
- `Improved Bots (Advanced)`

Analysis document:

`E:/diff/l4d2-mod-inspect/bot-ai-comparison.md`

Extracted parameter summary:

`E:/diff/l4d2-mod-inspect/_extracted-params.json`

Current judgment:

- `Improved Bots (Advanced)` is mostly cvar tuning and UI/menu changes.
- `Advanced Bot AI - Custom` is a large VScript behavior layer with tasks, timers, chat commands, settings, NetProps edits, and cvar overrides.
- Our prototype should borrow ideas, not start by modifying the large custom addon directly.

## Design Principle

Do not make bots simply stronger. Make them less synchronized, less robotic, and more legible.

Randomness should affect:

- When a bot reacts.
- Which bot responds first.
- How assertive a bot is.
- How closely a bot follows.
- Whether a low-risk interaction happens.

Randomness should not break:

- High-priority rescue behavior.
- Map progression.
- Safety from obvious hazards.
- Basic team cooperation.

Rule of thumb:

Randomize timing and style, not basic survival responsibility.

## Scope

### MVP Scope

The first prototype should include:

1. Debug switch and debug output.
2. Crash-safe coding pattern.
3. Small parameter boost layer.
4. Per-bot personality/profile generation.
5. Humanized reaction delay.
6. Basic wait/follow interaction.
7. One or two behavior experiments only.

Recommended first behavior experiments:

- Rescue reaction delay and role selection.
- Follow distance and mild leading behavior.

### Out Of Scope For First Version

Do not implement these first:

- Full combat AI replacement.
- Full item economy system.
- Tank/Witch advanced tactics.
- Machine learning.
- External AI service.
- SourceMod/native plugin.
- Complex nav editing.
- Full map objective automation.

## Debug Requirements

Debugging is a first-class requirement.

### Console Or Chat Switch

There should be a command to toggle debug mode.

Possible command names:

- `!hbot_debug`
- `!hbot_status`
- `!hbot_why`
- `!hbot_profile`
- `!hbot_reload`

If chat commands are awkward in VScript, console-driven commands are acceptable.

### Debug Output

When debug is on, the addon should report meaningful bot state.

Example:

```text
[HBOT] Coach task=rescue target=Ellis reason=hunter_pounce delay=0.82 score=91
[HBOT] Nick task=follow target=human reason=too_far distance=480 desired=260
[HBOT] Rochelle task=wait reason=human_low_health duration=2.1
```

Useful fields:

- Bot name.
- Current task.
- Target entity/player.
- Reason.
- Priority score.
- Delay.
- Cooldown.
- Personality/profile values.
- Whether the action was canceled.

### Debug File

Nice to have:

- Write a debug text file when enabled.
- File can be overwritten per round.
- File can include timestamp-like game time values.

Possible file path inside game script IO:

`humanized bot ai/debug.txt`

Need to verify whether `StringToFile` is usable in the target mode.

### Debug Safety

Debug output should be rate-limited.

Avoid printing every tick. Prefer:

- On task change.
- On important decision.
- On cancel.
- Once every few seconds for status.

## Crash Safety Requirements

L4D2 script crashes and game crashes can be hard to understand. The addon should be written defensively.

### Defensive Checks

Before touching any entity:

- Check entity is not null.
- Check entity is valid.
- Check player is alive when required.
- Check player is survivor/bot/human as expected.
- Check weapon/item exists before reading props.

### Timer Discipline

Avoid very frequent expensive loops.

Guidelines:

- No heavy full-entity scanning every frame.
- Prefer 0.25s, 0.5s, 1s, or event-driven checks.
- Separate fast safety checks from slow planning checks.
- Never recursively schedule unbounded timers.

### Feature Flags

Every behavior should be switchable.

Example:

```text
enable_rescue_delay = true
enable_personality = true
enable_mild_leading = true
enable_item_curiosity = false
enable_player_interaction = false
```

### Fail Closed

If a behavior errors or detects bad state, it should stop that behavior and let vanilla AI continue.

The addon should prefer doing nothing over forcing broken behavior.

## Mild AI Parameter Boost

The addon may slightly improve vanilla bot parameters, but should avoid aggressive values.

Potential cvar areas:

- Friend immobilized reaction time.
- Follow/separation range.
- Path lookahead.
- Close checkpoint door interval.
- Bot melee/team weapon behavior.
- Calm delay after combat.

Important: parameter boosts should be conditional and subtle.

### Dynamic Boost Triggers

The user suggested dynamic boosts when players are in trouble.

Possible triggers:

- Human player health is low.
- Human player recently took damage.
- Human player is incapacitated.
- Human player is pinned by special infected.
- Team is under heavy common infected pressure.
- Tank/Witch event is active.

Possible dynamic effects:

- Reduce rescue delay.
- Increase follow urgency.
- Slightly increase aim/turn speed.
- Increase willingness to shove.
- Increase willingness to throw pipe/molotov.
- Temporarily reduce hesitation.

These should have cooldowns and should decay back to normal.

Example:

```text
human_recently_damaged -> team_alert for 3s
team_alert -> reduce reaction delay by 20%
team_alert -> increase rescue score by 10
team_alert expires -> return to profile baseline
```

## Humanization Requirements

### Per-Bot Personality

Each survivor bot should receive a small profile each round.

Example dimensions:

| Trait | Meaning |
| --- | --- |
| reaction_speed | How quickly they respond. |
| rescue_bias | How likely they are to prioritize saving teammates. |
| follow_distance | Preferred distance from human/player group. |
| lead_bias | Willingness to move slightly ahead. |
| item_curiosity | How likely they are to inspect/pick nearby weapons/items. |
| throwable_bias | Willingness to use throwables. |
| wait_bias | Willingness to pause for lagging/low-health players. |
| interaction_bias | Willingness to do playful/attention-getting actions. |

Profiles should be bounded. No trait should create useless bots.

### Reaction Delay

Bots should not react in perfect sync.

Behavior examples:

- Rescue reactions get a randomized delay.
- Item pickup decisions get a randomized delay.
- Follow corrections get a randomized delay.
- Multiple bots should not all choose the same task instantly.

Delay should depend on task priority.

Example:

| Event | Suggested delay |
| --- | --- |
| Teammate pinned | 0.25s to 1.5s |
| Human low health | 0.8s to 3s |
| Weapon curiosity | 1s to 5s |
| Waiting interaction | 2s to 8s |

High-priority rescue should have shorter random delay than low-priority flavor behavior.

### Commitment And Cooldown

Bots should not flicker between tasks.

Add:

- Minimum task commitment time.
- Task cooldown after completion.
- Cancel conditions.

Example:

```text
If Coach chooses rescue, keep rescue intent for at least 0.8s unless Coach is pinned, incapacitated, or target is already safe.
```

## Candidate Behaviors

### 1. Rescue Behavior

Goal:

Bots save pinned/incapped teammates more believably, without instant synchronized reactions.

Design:

- Detect teammate pinned by Hunter/Jockey/Smoker/Charger.
- Score rescue task by distance, danger, bot personality, current weapon, and whether another bot already committed.
- Add reaction delay.
- Only one or two bots should respond.
- Other bots can cover or continue fighting.

Debug:

```text
[HBOT] Ellis rescue_score=87 target=Nick reason=smoker_tongue delay=0.61 committed=true
```

### 2. Follow And Mild Leading

Goal:

Bots should not rely entirely on the player to lead, but should not run away.

Design:

- Each bot has a preferred follow distance.
- Some bots may move slightly ahead when the team is safe.
- Leading should stop when:
  - human health is low,
  - horde is active,
  - special infected threat is active,
  - distance exceeds max safe range,
  - map objective requires grouping.

Potential values:

```text
follow_distance = 180 to 320
mild_lead_distance = 100 to 350 ahead
max_separation = 650 to 900
```

### 3. Waiting And Interaction

Goal:

If the team is stalled, bots show mild interaction instead of standing silently.

Triggers:

- Team has not advanced for a long time.
- Human is idle or looking away.
- Human is low health and lagging behind.
- Safe area or low-danger state.

Possible actions:

- Stop and face player.
- Vocalize.
- Move near player.
- Shove nearby common infected.
- Light attention-getting behavior.

User idea:

Bots may shoot at the player to get attention because bot friendly fire may not hurt players.

Design caution:

This should be optional and conservative. Prefer fake/low-risk interaction first:

- Look at player.
- Vocalize.
- Step closer.
- Aim near player but do not fire.
- Fire only if friendly-fire safety is confirmed.

Feature flag:

```text
enable_playful_attention_fire = false
```

### 4. Weapon Selection And Item Curiosity

Goal:

Bots should look more alive around weapons/items.

User behavior idea:

- Near multiple weapons, bots may switch between choices.
- Bots may actively pick up newly seen weapons.
- Bots should care about throwables.

Design:

- Add item curiosity score.
- Let bots inspect nearby weapons with a delay.
- Avoid constant weapon swapping.
- Respect role/profile.
- Do not steal critical items from humans.

Candidate rules:

- If bot has weak weapon and sees better weapon nearby, consider pickup.
- If several weapons are nearby, bot may hesitate or compare.
- If human is nearby and lacks item, bot may avoid taking the best item.
- Throwables should have profile-based preference.

Cooldowns:

```text
weapon_switch_cooldown = 20s to 45s
item_curiosity_check_interval = 2s to 5s
recently_rejected_item_cooldown = 30s
```

### 5. Melee Support

Question:

Can bots use melee weapons?

Known reference:

Both reference mods touch melee-related behavior:

- Old mod uses `sb_max_team_melee_weapons`.
- New mod has `Melee`, `MeleeLimit`, and custom fire/melee handling.

Requirement:

Investigate whether a clean prototype can allow limited bot melee use without breaking combat behavior.

MVP:

- Do not make melee a first behavior unless easy.
- Document what cvars/scripts are required.
- Keep melee limit small.

Potential default:

```text
enable_melee = false initially
melee_limit = 1
```

## Configuration Requirements

Settings should be centralized.

Example:

```text
enable_debug = false
enable_personality = true
enable_rescue_delay = true
enable_mild_leading = true
enable_wait_interaction = true
enable_item_curiosity = false
enable_melee = false

base_follow_distance = 240
max_separation = 800
rescue_min_delay = 0.25
rescue_max_delay = 1.5
stall_interaction_time = 20
```

Prefer config values that can be reloaded or changed through commands.

## Testing Requirements

Because L4D2 loading is slow, every behavior needs a repeatable test.

### Test Scenarios

Minimum test scenarios:

- Hunter pins human.
- Smoker pulls human.
- Jockey rides human.
- Human low health.
- Human idle/stalled.
- Multiple weapons nearby.
- Throwable nearby.
- Bot too far from human.
- Bot stuck.

### Fast Feedback Goal

Need a quick way to run a map and validate:

- Addon loaded.
- Debug command works.
- Bot profiles generated.
- Current tasks visible.
- No script error spam.

## Open Questions

1. Which L4D2 mode should be supported first?
   - Single player?
   - Local server co-op?
   - Dedicated server?

2. Which debug channel is most practical?
   - Chat print?
   - Console print?
   - HUD text?
   - File output?

3. Should the first prototype be a clean addon, or a fork of `Advanced Bot AI - Custom`?

4. How much "playful interaction" is acceptable before it becomes annoying?

5. Should bots ever fire near/at players?
   - Needs friendly-fire confirmation.
   - Should be off by default.

6. Should bots be allowed to lead?
   - If yes, only mildly and only in safe states.

7. Should melee be part of v1?
   - Probably no, unless investigation shows it is simple.

## Proposed First Milestone

Milestone 1: Debuggable Humanizer Skeleton

Deliverables:

- New prototype addon folder.
- Addon loads in game.
- Debug command works.
- Per-bot profile generated and printed.
- No behavior modification yet except safe debug output.
- Optional settings file.

Success criteria:

```text
Game loads without crash.
Console/chat shows: Humanized Bot AI loaded.
!hbot_profile prints each bot profile.
!hbot_debug toggles debug mode.
```

Milestone 2: Rescue Delay Experiment

Deliverables:

- Detect pinned teammate.
- Pick one responding bot.
- Apply personality-based delay.
- Print reason and delay.
- Avoid duplicate synchronized response.

Milestone 3: Follow And Wait Experiment

Deliverables:

- Per-bot follow distance.
- Mild leading in safe states.
- Stalled-team interaction.
- Debug visible task reason.

## Practical Recommendation

Build our own small prototype, but only after the debug skeleton exists.

Do not start by tuning dozens of combat parameters. Do not start by copying the whole large addon.

The first valuable artifact is not smarter bots. It is observability.

