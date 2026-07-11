// gxLdBot config module: THE single authoritative source of tunables.
//
// DESIGN 7.2: previously the Settings table was defined THREE times (a dead
// init block, gxldbotDefaultSettings, and a verbatim copy inside the escort
// preset). This module collapses them into one: DefaultSettings is the only
// place a default value lives; presets store ONLY their diff from default.
//
// LOAD-ORDER CONTRACT: main.nut includes this FIRST (before all behavior
// modules), because everything reads GxLdBot.Settings.
//
// INVARIANT THAT MUST NOT BREAK (DESIGN 7.2): ApplyDefaultSettings() writes
// every default onto GxLdBot.Settings UNCONDITIONALLY on every include. This
// is what survives L4D2 map transitions (the old code relied on the same
// unconditional foreach). Do NOT "optimize" it to write-only-if-missing, or
// runtime settings would leak across maps and break mode switching.

if (!("GxLdBot" in getroottable())) {
	::GxLdBot <- {};
}

if (!("SetTableSlot" in GxLdBot)) {
	GxLdBot.SetTableSlot <- function(tbl, key, value) {
		if (key in tbl) { tbl[key] = value; } else { tbl[key] <- value; }
	};
}

// ---- authoritative defaults (the ONLY place a default value lives) --------
GxLdBot.DefaultSettings <- {
	Mode = "player",
	EnableMildCvars = true,
	EnableProfiles = true,
	EnableObservation = true,
	EnableDebugFile = false,
	// DIAGNOSTIC black box (temporary): writes a single marker line to
	// gxldbot/blackbox.txt immediately before/after each native nav call
	// (NavAreaBuildPath / GetNavAreasInRadius). Squirrel try/catch cannot catch an
	// engine-level crash inside a native call, so after a crash the LAST line in
	// blackbox.txt names the call that was in flight. Turn off once the crash
	// source is found. Kept out of PresetKeys so it stays globally on until removed.
	// OFF for the shipped build (crash was traced to engine.dll / external, not our
	// nav calls). Flip true to re-arm the black box if a new crash needs tracing.
	BlackBoxEnable = false,
	// PERSISTENT game log (default ON): a growing session log written to
	// gxldbot/gamelog.txt. Unlike DebugBuffer (last 80 lines, overwrite), this keeps
	// the whole session in memory and rewrites the full file each flush, so the file
	// GROWS across a play session. GameLogInterval = seconds between per-bot snapshot
	// rows; GameLogMaxLines caps memory so a very long session can't grow unbounded
	// (oldest rows drop). Snapshots capture hp/role/action/dist-to-human/phase/heal
	// intent so we can data-mine handfeel + heal issues after a play session.
	// OFF for the shipped build (per-tick snapshot + periodic file rewrite has I/O
	// cost). Flip true to re-enable data-mining a play session.
	EnableGameLog = false,
	GameLogInterval = 1.0,
	GameLogFlushInterval = 3.0,
	GameLogMaxLines = 4000,
	EnableChatEvents = true,
	EnableMultiplayerGuard = true,
	EnableCallouts = true,
	EnableRoles = true,
	EnableFocus = true,
	EnableClaims = true,
	EnableComposure = true,
	EnableResourceStyle = true,
	EnableIdle = true,
	EnableCards = true,
	EnableScout = true,
	EnableProgress = true,
	EnableGoof = true,
	EnableWorldModel = true,
	EnableExpressions = true,
	EnableStyleMemory = true,
	EnableNativeDirectiveProbe = true,
	DebugBufferLimit = 80,
	PersonalLeadMin = 35,
	PersonalLeadMax = 100,
	WaitBiasMin = 0,
	WaitBiasMax = 60,
	ItemCuriosityMin = 30,
	ItemCuriosityMax = 100,
	InteractionBiasMin = 30,
	InteractionBiasMax = 100,
	HealThresholdMin = 12,
	HealThresholdMax = 45,
	BaseFollowDistance = 220,
	FollowDistanceJitter = 60,
	MaxSeparation = 620,
	SquadDispersionMax = 900.0,
	EscortCatchupDistance = 420.0,
	// Buddy formation slice 1A. The point owns the far forward claim; the relay
	// owns a second, shorter lead so the human sees two distinct route-setters.
	FormationInterval = 0.45,
	RelayFlowFraction = 0.85,
	SupportLinkDistance = 780.0,
	SupportLinkFlow = 1200.0,
	SupportLinkMaxZ = 110.0,
	SupportCacheSeconds = 0.35,
	// Until reverse NavAreaBuildPath is probed in-game, proactive targets remain
	// inside a conservative direct-distance/drop envelope and must link back to
	// the human-connected support component.
	UnprovenForwardMaxDistance = 950.0,
	UnprovenForwardMaxDrop = 120.0,
	ReversePathEnable = true,
	ReversePathMaxLeadDistance = 1250.0,
	ReversePathMaxLength = 10000.0,
	ReversePathCacheSeconds = 0.45,
	ReversePathProbeDebug = false,
	// Rubber-band movespeed: a bot that is both dispersed and behind in map flow
	// gets a leased boost to rejoin. The driver only writes targets above 1.0 and
	// never touches a current value below 1.0, preserving engine slow effects.
	RubberBandEnable = true,
	RubberBandNearDist = 500.0,
	RubberBandFarDist = 1100.0,
	RubberBandMaxSpeed = 1.5,
	// FLOW-BEHIND catch-up (player: "I play aggressive / rush ahead; a real skilled
	// teammate keeps up, not trails 500 flow behind"). The old rubber-band scaled its
	// boost by distance to the SQUAD CENTROID, which fails exactly when the human
	// solo-rushes: the two other bots cluster together, the lagging bot is near THAT
	// centroid, so it never boosted even while hundreds of flow behind the player.
	// Now the boost scales by how far this bot is BEHIND THE HUMAN IN FLOW: 0 at
	// RubberBandFlowNear, full RubberBandMaxSpeed at RubberBandFlowFar. Takes the max
	// of this and the old centroid term, so both "spread out" and "human rushed off"
	// trigger the boost. This is what lets bots keep up with an aggressive player.
	RubberBandFlowNear = 150.0,
	RubberBandFlowFar = 1200.0,
	ActiveAdvanceDelay = 6.0,
	ActiveAdvanceFlowBoost = 180.0,
	StallSeconds = 4.0,
	TeamMoveThreshold = 55.0,
	DebugStatusInterval = 5.0,
	RescueDelayMin = 0.25,
	RescueDelayMax = 1.1,
	// Perception delay (DESIGN 3, layer 2): when the shared situation flips to
	// "emergency", each bot only "notices" after a personality-scaled random lag,
	// so four bots never change stance on the same tick (that swarm-mind sync is
	// the single most robotic tell). Kept deliberately small per the player's "a
	// little, not too much" — base window, scaled by ReactionScale (~0.8..1.6).
	PerceiveDelayMin = 0.1,
	PerceiveDelayMax = 0.5,
	WorldFrameInterval = 0.45,
	// Per-arbiter-tick heavy-work budget (nav expansion + reverse-path build +
	// infected slice scan). Was effectively 1 (a single bool), which made the
	// point and relay FIGHT over the one slot: whichever lost held still that
	// tick, so the two leaders alternated walk/stop ("走一步停一步"). Raising it
	// to 3 lets point + relay both expand nav on the same tick (continuous lead,
	// like the early version) while still capping total heavy ops so the PERF
	// spikes GPT's slice budget was added to prevent don't return.
	HeavySliceMax = 3,
	ThreatFrameRadius = 760.0,
	ThreatSliceInterval = 0.35,
	ThreatSpecialInterval = 0.5,
	ThreatRecordMaxAge = 2.6,
	TeamAlertHold = 1.4,
	AftermathMinSeconds = 1.8,
	AftermathMaxSeconds = 4.0,
	AftermathStressExit = 20.0,
	StressRisePerSecond = 48.0,
	StressDecayPerSecond = 18.0,
	MomentumGainPerSecond = 4.0,
	MomentumLossPerSecond = 16.0,
	MindUpdateInterval = 0.45,
	CalloutCooldown = 0.9,
	ThreatScanRadius = 1450.0,
	FocusSwitchCost = 0.22,
	ClaimExpiry = 1.8,
	ScoutInterval = 0.65,
	ScoutAheadDistance = 320.0,
	ScoutSideOffset = 160.0,
	ScoutMaxHumanDistance = 480.0,
	ScoutMinRetargetDistance = 120.0,
	ScoutRepeatTargetDistance = 260.0,
	ScoutRepeatInterval = 4.0,
	ScoutCombatRadius = 340.0,
	ScoutSpecialCombatRadius = 1000.0,
	// Dynamic advance (player request #3/#4): instead of a hard STOP whenever any
	// zombie is near, forward pressure SLOWS with threat and only stops for real
	// danger. Severity 0 (clear / a stray common) = full speed; 1 (a genuine crowd
	// of commons, count >= DynamicSlowCommonCount, no special) = advance but with a
	// reduced forward lead (lead x DynamicSlowLeadMul, so it steps forward more
	// cautiously, never freezes); 2 (any special/witch nearby, or an overwhelming
	// common mob, count >= DynamicHeavyCommonCount) = hold and let combat resolve.
	// Set DynamicAdvanceEnable=false for the old binary stop.
	DynamicAdvanceEnable = true,
	DynamicSlowCommonCount = 4,
	DynamicHeavyCommonCount = 9,
	DynamicSlowLeadMul = 0.5,
	// STRAGGLER REGROUP (swamp/mud fix): in slow terrain the rear can't keep up and
	// falls far behind while the point keeps pushing on flow. Rather than fight the
	// engine's terrain slowdown (which owns m_flLaggedMovementValue and blocks our
	// rubber-band boost), we cap how far the point/relay may lead the MOST-BEHIND
	// alive teammate: once the lead over the straggler exceeds RegroupStretchFlow the
	// forward target is pulled back toward the straggler (the leader eases up so the
	// team closes the gap); past RegroupHardFlow the leader holds near the straggler
	// until they catch up. Measured in flow units (same axis as the map objective),
	// so it works regardless of what NetProp the terrain slowdown uses. 0 disables.
	RegroupStretchFlow = 650.0,
	RegroupHardFlow = 1100.0,
	ProgressInterval = 0.6,
	// While the human is actively moving, re-target this often (much shorter
	// than ProgressInterval) so a leading scout stays AHEAD instead of lagging a
	// beat behind the player who is holding W (fix for "bot just trails me").
	ScoutMovingInterval = 0.22,
	RelayProgressInterval = 0.30,
	ProgressScanRadius = 900.0,
	ProgressMaxAreas = 96,
	// Gradient-flow pathing (layer-2, nav-probe verified): instead of scanning the
	// whole ProgressScanRadius sphere every tick, walk the nav-area adjacency graph
	// N steps toward higher flow. ~5 adjacency queries/step vs ~96 area scans =
	// roughly 1/10 the cost. Steps set how far ahead the breadcrumb target lands.
	// 0 disables gradient and forces the old radius scan (fail-safe).
	ProgressGradientSteps = 6,
	ProgressMinAdvanceFlow = 15.0,
	ProgressFlowTolerance = 50.0,
	ProgressRetargetDistance = 90.0,
	ProgressMaxLeadFlow = 760.0,
	StallProbeExtraFlow = 220.0,
	// Endpoint protection (DESIGN 5.5 point-of-no-return): once ANY survivor has
	// entered the exit saferoom, a bot must NOT push its flow past the human's —
	// otherwise the aggressive lead walks it through the exit door / into a
	// close-off dead zone, and closing the saferoom strands it outside (a
	// run-ending bug). true = clamp lead to the human once the exit is in play.
	EndpointHoldEnable = true,
	// Small flow slack a bot may still lead by while the exit is in play — enough
	// to stay at the doorway with the human, not enough to run through it. Keep
	// well below the door's flow depth so a bot never crosses the finish trigger.
	EndpointHoldFlowMargin = 60.0,
	// Constant forward lead (flow units) the POINT bot carries so it walks ahead
	// as a living breadcrumb even while the human creeps along (fixes "I get lost,
	// no bot leads the way"). The flanker gets ScoutLeadFlow * ScoutFlankerLeadMul
	// (a mid relay between you and the point); anchor/follower ignore this entirely
	// and stay tethered (防孤立铁律不变). This is the scout-group formation:
	// point = forward guide, flanker = relay, anchor = rear escort.
	ScoutLeadFlow = 320.0,
	ScoutFlankerLeadMul = 0.5,
	// Lead body-length (flow) a point must ESTABLISH before it is allowed to stop and
	// guide-hold. When bot and human are roughly level (data: clear-combat, bf-hf ~+56,
	// 54 frames), the old "hold once at all ahead" let the point sit level with you and
	// hand back to vanilla-follow — the "带路不积极" passivity: it never stepped out to
	// actually be IN FRONT. Now a nearby forward target is only treated as "arrived,
	// hold" once the point already leads by this much; below it, the point keeps
	// stepping forward to build a real body-length lead first.
	LeadEstablishedFlow = 120.0,
	LeadFlowPerBias = 12.0,
	EmergencyThreatRadius = 1800.0,
	EmergencyCommonRadius = 650.0,
	EmergencyAssistMultiplier = 2.0,
	IdleWanderRadius = 130.0,
	IdleWaitBiasGate = 12,
	IdleScoutAlways = true,
	// Build cards are chapter-scoped. Core identity never changes on a timer.
	CardRerollInterval = 0.0,
	CardRerollChance = 0,
	EnableActions = true,
	// Vanilla rescue remains the safe default while the driver/lease and
	// perception layers are being rebuilt. Scripted rescue stays implemented and
	// flag-gated for a later isolated validation pass.
	EnableRescue = false,
	EnableRetreat = true,
	EnableCover = true,
	EnableShove = true,
	EnableAssist = true,
	// Scripted self-heal is OFF: the enact path only forced BTN_USE, which does
	// NOT trigger a medkit self-heal in L4D2 (that needs equip-medkit + attack),
	// so a low-HP bot would just stand pressing a no-op key for HealDuration —
	// AND heal outranks escort/progress/guide in the arbiter, so the rear bot got
	// stuck in place not advancing (player report "last bot freezes behind").
	// Vanilla already self-heals bots when safe (README roadmap note), so we hand
	// it back to vanilla instead of half-driving it. Re-enable only if the full
	// FL_FROZEN + equip + force-attack recipe is implemented in the enact block.
	EnableHeal = false,
	ArbiterInterval = 0.22,
	AttackCommandRefresh = 0.65,
	MoveCommandRefresh = 2.4,
	TeamAssistPlanSeconds = 1.0,
	RescueShoveRange = 105.0,
	// Max distance a bot will commit to a scripted rescue. Beyond this, don't pull
	// a bot across the map into danger — leave it to whoever is closer (or vanilla).
	RescueMaxDistance = 1400.0,
	HealDuration = 6.2,
	CombatShoveRadius = 115.0,
	CombatShoveSpecialRadius = 145.0,
	CombatShoveDuration = 0.28,
	CombatShoveCooldown = 0.38,
	// A lone common is shot, not shoved (real players only melee-shove when
	// swarmed). Only shove commons when at least this many are inside
	// CombatShoveRadius. Specials still trigger a shove regardless.
	CombatShoveCommonCount = 3,
	// Global floor between combat shoves for one bot (seconds). This is the hard
	// "stop spamming shove" limit the player asked for — a bot melee-shoves at most
	// once per this window, no matter how many zombies are around. RESCUE shoves are
	// exempt (breaking a pin needs repeated shoves). Stacks with CombatShoveCooldown;
	// whichever is longer wins.
	ShoveGlobalCooldown = 5.0,
	// Vertical band (units) for the same-floor reachability filter. A L4D2 floor
	// is ~128-200 units; 110 accepts same-floor slopes/stairs but rejects a zombie
	// a full storey up/down. Kills the "shove/swing at unreachable air" bug.
	ReachableMaxZ = 110.0,
	// Living micro-movement (player request "bots look inert, standing statue-still").
	// While a scout holds a guide point or a bot idles, it does small idle fidgets:
	// it shifts its hold spot by up to FidgetRadius every FidgetInterval-ish seconds
	// (a weight-shift / reposition, not a march), and looks around instead of
	// laser-locking the human — a subtle "alive, waiting" tell. All bounded so it
	// never drifts off station or re-creates the old "左右来回蹭" jitter. Set
	// FidgetEnable=false for dead-still holds.
	FidgetEnable = true,
	FidgetRadius = 55.0,
	FidgetInterval = 2.6,
	FidgetLookChance = 35,
	GuideGazePulseMin = 3.5,
	GuideGazePulseMax = 5.5,
	GuideGazeOnlySafe = true,
	GuideCheckBackDelay = 12.0,
	GuideCheckBackMinDistance = 360.0,
	GuideCheckBackStopDistance = 220.0,
	GuideCheckBackMaxDuration = 6.0,
	GuideCheckBackCooldown = 10.0,
	// Goof-off (DESIGN 6.3): zero-physical-risk idle antics near the human when
	// nothing else to do — crouch-spam (teabag) + face the human. No shove
	// (griefing risk), no flashlight yet (needs a verified NetProp).
	GoofChance = 35,
	GoofMinInterval = 6.0,
	GoofMaxInterval = 16.0,
	GoofDuration = 1.4,
	GoofCrouchToggle = 0.22,
	GoofHumanRadius = 260.0,
	// Group teabag (player request): when one bot starts an antic, nearby idle bots
	// may JOIN in within GoofJoinWindow seconds (chance GoofJoinChance each), so you
	// occasionally get a couple bots teabagging together — but a team-wide cooldown
	// (GoofTeamCooldown) gates how often the whole squad can do it, so it never gets
	// spammy. Set GoofJoinChance = 0 to go back to strictly-staggered solo antics.
	GoofJoinChance = 55,
	GoofJoinWindow = 1.2,
	GoofTeamCooldown = 14.0,
	ExpressionPlanInterval = 0.55,
	ExpressionTeamCooldown = 7.0,
	ExpressionMinStall = 2.0,
	ExpressionJoinChance = 45,
	ExpressionJoinDelayMin = 0.4,
	ExpressionJoinDelayMax = 1.5,
	ExpressionAttentionDuration = 1.1,
	ExpressionCheckinDuration = 1.0,
	ExpressionEnergyGain = 7.0,
	ExpressionEnergyCost = 38.0,
	ExpressionAttentionRadius = 620.0,
	ExpressionAftermathStressMax = 48.0,
	PlayerDirectiveSeconds = 8.0,
	PlayerWaitLeadFlow = 90.0,
	PlayerMoveOnFlowBoost = 180.0,
	ReviveProximity = 100.0,
	RetreatHpThreshold = 22,
	RetreatCommonRadius = 120.0,
	RetreatCommonCount = 6,
	RetreatDuration = 0.35,
	RetreatCooldown = 0.9,
	CoverGuardDistance = 220.0,
	AssistCommonRadius = 430.0,
	AssistCommonCount = 2,
	AssistMaxDistance = 900.0,
	AssistDuration = 1.15,
	HealCombatRadius = 300.0,
	HealCommonCount = 3,
	// "Follow the human, don't wander off to clear trash" (player request). When
	// the human has moved within HumanMovingWindow seconds, a bot is considered to
	// be traveling WITH the human: optional close-horde assist is suppressed so it
	// keeps pace / leads instead of peeling off to kill commons. Assist still fires
	// when the human is stationary (holding a spot → help clear) or in a real
	// emergency (teammate swarmed/pinned — that path bypasses this gate). Set
	// AssistYieldWhenMoving = false to restore always-on assist.
	AssistYieldWhenMoving = true,
	HumanMovingWindow = 1.8,
	// SELF-DEFENSE override: even while traveling with a moving human (assist
	// otherwise suppressed), a bot that is ITSELF being swarmed by at least this
	// many reachable commons still fights back — travel discipline must never
	// make a bot stand there getting eaten. Lower than AssistCommonCount so a bot
	// defends itself a touch earlier than it would peel off to help someone else.
	AssistSelfDefenseCount = 2,
};

// ---- keys seeded into every preset (behavior keys, no meta) ---------------
// BuildModePresets seeds EXACTLY these from DefaultSettings, then applies the
// per-mode diff on top. Never more, never fewer.
GxLdBot.PresetKeys <- [
	"PersonalLeadMin", "PersonalLeadMax", "WaitBiasMin", "WaitBiasMax", "ItemCuriosityMin",
	"ItemCuriosityMax", "InteractionBiasMin", "InteractionBiasMax", "HealThresholdMin",
	"HealThresholdMax", "BaseFollowDistance", "FollowDistanceJitter", "MaxSeparation",
	"EscortCatchupDistance", "ActiveAdvanceDelay", "ActiveAdvanceFlowBoost", "StallSeconds",
	"RelayFlowFraction", "SupportLinkDistance", "UnprovenForwardMaxDistance",
	"ReversePathMaxLeadDistance", "RubberBandEnable", "RubberBandNearDist",
	"RubberBandFarDist", "RubberBandMaxSpeed",
	"ScoutAheadDistance", "ScoutSideOffset", "ScoutMaxHumanDistance",
	"ScoutMinRetargetDistance", "ScoutRepeatTargetDistance", "ScoutRepeatInterval",
	"ScoutCombatRadius", "ScoutSpecialCombatRadius", "ProgressInterval",
	"ScoutMovingInterval", "RelayProgressInterval",
	"ProgressScanRadius", "ProgressMinAdvanceFlow", "ProgressFlowTolerance",
	"ProgressRetargetDistance", "ProgressMaxLeadFlow", "StallProbeExtraFlow",
	"ScoutLeadFlow", "ScoutFlankerLeadMul",
	"LeadFlowPerBias", "IdleWanderRadius", "IdleWaitBiasGate", "IdleScoutAlways",
	"HealDuration", "CombatShoveRadius", "CombatShoveSpecialRadius", "CombatShoveDuration",
	"CombatShoveCooldown", "RetreatHpThreshold", "RetreatCommonCount", "RetreatDuration",
	"RetreatCooldown", "AssistCommonRadius", "AssistCommonCount", "AssistMaxDistance",
	"AssistDuration", "HealCombatRadius", "HealCommonCount",
	"TeamAlertHold", "AftermathMinSeconds", "AftermathMaxSeconds", "AftermathStressExit",
	"StressRisePerSecond", "StressDecayPerSecond", "MomentumGainPerSecond",
	"MomentumLossPerSecond", "ExpressionTeamCooldown", "ExpressionMinStall",
	"ExpressionEnergyGain", "ExpressionEnergyCost", "PlayerDirectiveSeconds",
	"PlayerWaitLeadFlow", "PlayerMoveOnFlowBoost",
];

// ---- per-mode diffs (ONLY what differs from DefaultSettings) --------------
GxLdBot.ModePresetDiffs <- {
	player = {
		label = "player",
		desc = "active player-like buddy",
		PersonalLeadMin = 45,
		WaitBiasMax = 75,
		ItemCuriosityMin = 45,
		InteractionBiasMin = 45,
		HealThresholdMin = 30,
		HealThresholdMax = 62,
		BaseFollowDistance = 240,
		FollowDistanceJitter = 85,
		// EXPERIMENTAL AGGRO BUILD: point/relay lead roughly DOUBLE the distance
		// from the human, push ahead sooner, and wait less. Revert this preset to
		// the pre-exp values (820/640/780/950/1250/2.2/360/3.0) if bots range too
		// far and get isolated. The reverse-path + support-chain safety still gates
		// the far end (>UnprovenForwardMaxDistance needs a proven path), so this
		// widens the LEASH, not the safety proof.
		MaxSeparation = 1400,
		// Rear/flex catch-up leash = the DISTANCE-BEHIND at which a trailing bot
		// abandons whatever it's doing and runs back to the human. This is the
		// "断后不能太远" knob and is DELIBERATELY DECOUPLED from the forward-lead
		// distances (UnprovenForwardMaxDistance / ReversePathMaxLeadDistance below):
		// the player wants point/relay to lead FAR ahead (1900/2500) but the rear
		// guard to stay CLOSE so it never drops out of a "whole-squad enters" trigger
		// (the co-op cart / elevator node) and never gets far enough behind to trip
		// vanilla's auto-teleport. A prior aggressive pass raised this to 1100 in
		// lockstep with the forward knobs, which is what made the rear straggle.
		EscortCatchupDistance = 550.0,
		RelayFlowFraction = 0.85,
		SupportLinkDistance = 1560.0,
		UnprovenForwardMaxDistance = 1900.0,
		ReversePathMaxLeadDistance = 2500.0,
		ActiveAdvanceDelay = 1.0,
		ActiveAdvanceFlowBoost = 520.0,
		StallSeconds = 3.0,
		ScoutAheadDistance = 430.0,
		ScoutSideOffset = 190.0,
		ScoutMaxHumanDistance = 700.0,
		ScoutMinRetargetDistance = 105.0,
		ScoutRepeatTargetDistance = 230.0,
		ScoutRepeatInterval = 3.2,
		ScoutCombatRadius = 330.0,
		ScoutSpecialCombatRadius = 1100.0,
		ProgressInterval = 0.45,
		ScoutMovingInterval = 0.22,
		RelayProgressInterval = 0.30,
		ProgressScanRadius = 1050.0,
		ProgressMinAdvanceFlow = 12.0,
		ProgressFlowTolerance = 38.0,
		ProgressRetargetDistance = 80.0,
		ProgressMaxLeadFlow = 1400.0,
		LeadFlowPerBias = 15.0,
		IdleWanderRadius = 175.0,
		IdleWaitBiasGate = 28,
		CombatShoveRadius = 135.0,
		CombatShoveSpecialRadius = 180.0,
		CombatShoveDuration = 0.30,
		CombatShoveCooldown = 0.24,
		RetreatHpThreshold = 16,
		RetreatCommonCount = 8,
		RetreatDuration = 0.25,
		RetreatCooldown = 0.65,
		AssistCommonRadius = 540.0,
		AssistCommonCount = 1,
		AssistMaxDistance = 1250.0,
		AssistDuration = 1.35,
		HealCombatRadius = 240.0,
		HealCommonCount = 5,
		StallProbeExtraFlow = 720.0,
		ScoutLeadFlow = 640.0,
	},
	escort = {
		label = "escort",
		desc = "0.6.3 human-centered escort behavior",
		RelayFlowFraction = 0.60,
		SupportLinkDistance = 620.0,
		UnprovenForwardMaxDistance = 600.0,
		ReversePathMaxLeadDistance = 800.0,
		ScoutMovingInterval = 0.35,
		RelayProgressInterval = 0.55,
		RubberBandNearDist = 560.0,
		RubberBandFarDist = 1150.0,
		RubberBandMaxSpeed = 1.28,
	},
	safe = {
		label = "safe",
		desc = "conservative debug-friendly behavior",
		PersonalLeadMin = 20,
		PersonalLeadMax = 80,
		WaitBiasMin = 5,
		WaitBiasMax = 70,
		ItemCuriosityMin = 20,
		ItemCuriosityMax = 80,
		InteractionBiasMin = 20,
		InteractionBiasMax = 75,
		HealThresholdMin = 22,
		HealThresholdMax = 52,
		BaseFollowDistance = 205,
		FollowDistanceJitter = 45,
		MaxSeparation = 520,
		EscortCatchupDistance = 340.0,
		RelayFlowFraction = 0.55,
		SupportLinkDistance = 520.0,
		UnprovenForwardMaxDistance = 520.0,
		ReversePathMaxLeadDistance = 650.0,
		ScoutMovingInterval = 0.45,
		RelayProgressInterval = 0.80,
		RubberBandNearDist = 620.0,
		RubberBandFarDist = 1200.0,
		RubberBandMaxSpeed = 1.22,
		ActiveAdvanceDelay = 8.0,
		ActiveAdvanceFlowBoost = 90.0,
		StallSeconds = 6.0,
		ScoutAheadDistance = 240.0,
		ScoutSideOffset = 120.0,
		ScoutMaxHumanDistance = 380.0,
		ScoutMinRetargetDistance = 140.0,
		ScoutRepeatTargetDistance = 300.0,
		ScoutRepeatInterval = 5.0,
		ScoutCombatRadius = 380.0,
		ScoutSpecialCombatRadius = 1200.0,
		ProgressInterval = 0.8,
		ProgressScanRadius = 700.0,
		ProgressMinAdvanceFlow = 25.0,
		ProgressFlowTolerance = 70.0,
		ProgressRetargetDistance = 110.0,
		ProgressMaxLeadFlow = 420.0,
		LeadFlowPerBias = 7.0,
		IdleWanderRadius = 90.0,
		IdleWaitBiasGate = 8,
		IdleScoutAlways = false,
		CombatShoveRadius = 95.0,
		CombatShoveSpecialRadius = 125.0,
		CombatShoveDuration = 0.25,
		CombatShoveCooldown = 0.65,
		RetreatHpThreshold = 24,
		RetreatCommonCount = 5,
		RetreatCooldown = 1.1,
		AssistCommonRadius = 380.0,
		AssistCommonCount = 3,
		AssistMaxDistance = 750.0,
		AssistDuration = 1.0,
		HealCombatRadius = 320.0,
		StallProbeExtraFlow = 240.0,
		ScoutLeadFlow = 150.0,
	},
};

// ---- application helpers --------------------------------------------------
// Apply the authoritative defaults onto GxLdBot.Settings. UNCONDITIONAL
// (see invariant note at top).
GxLdBot.ApplyDefaultSettings <- function() {
	if (!("Settings" in GxLdBot)) { GxLdBot.Settings <- {}; }
	foreach (key, value in GxLdBot.DefaultSettings) {
		GxLdBot.SetTableSlot(GxLdBot.Settings, key, value);
	}
};

// Expand preset diffs into full tables (label + desc + all behavior keys
// seeded from DefaultSettings), so ApplyMode()'s overwrite-only loop restores
// every behavior key when switching modes without a map reload.
GxLdBot.BuildModePresets <- function() {
	local out = {};
	foreach (name, diff in GxLdBot.ModePresetDiffs) {
		local full = {};
		full.label <- ("label" in diff) ? diff.label : name;
		full.desc <- ("desc" in diff) ? diff.desc : name;
		foreach (k in GxLdBot.PresetKeys) {
			full[k] <- GxLdBot.DefaultSettings[k];
		}
		foreach (k, v in diff) {
			if (k == "label" || k == "desc") { continue; }
			full[k] <- v;
		}
		out[name] <- full;
	}
	GxLdBot.SetTableSlot(GxLdBot, "ModePresets", out);
};

// Run both now so Settings + ModePresets exist immediately on include.
GxLdBot.ApplyDefaultSettings();
GxLdBot.BuildModePresets();
