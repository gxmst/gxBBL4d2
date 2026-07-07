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
	// Rubber-band movespeed (DESIGN §10 #1/#3): a bot far from the squad centroid
	// speeds up so it can rejoin instead of trailing and getting surrounded. Speed
	// scales linearly from 1.0 at RubberBandNearDist to RubberBandMaxSpeed at
	// RubberBandFarDist, applied via m_flLaggedMovementValue. Combined with speed
	// cards by taking the max of the two. Normal in-formation play is untouched.
	RubberBandEnable = true,
	RubberBandNearDist = 500.0,
	RubberBandFarDist = 1100.0,
	RubberBandMaxSpeed = 1.35,
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
	ProgressInterval = 0.6,
	ProgressScanRadius = 900.0,
	ProgressMaxAreas = 96,
	// Gradient-flow pathing (layer-2, nav-probe verified): instead of scanning the
	// whole ProgressScanRadius sphere every tick, walk the nav-area adjacency graph
	// N steps toward higher flow. ~5 adjacency queries/step vs ~96 area scans =
	// roughly 1/10 the cost. Steps set how far ahead the breadcrumb target lands.
	// 0 disables gradient and forces the old radius scan (fail-safe).
	ProgressGradientSteps = 4,
	ProgressMinAdvanceFlow = 15.0,
	ProgressFlowTolerance = 50.0,
	ProgressRetargetDistance = 90.0,
	ProgressMaxLeadFlow = 760.0,
	StallProbeExtraFlow = 220.0,
	// Constant forward lead (flow units) the POINT bot carries so it walks ahead
	// as a living breadcrumb even while the human creeps along (fixes "I get lost,
	// no bot leads the way"). The flanker gets ScoutLeadFlow * ScoutFlankerLeadMul
	// (a mid relay between you and the point); anchor/follower ignore this entirely
	// and stay tethered (防孤立铁律不变). This is the scout-group formation:
	// point = forward guide, flanker = relay, anchor = rear escort.
	ScoutLeadFlow = 320.0,
	ScoutFlankerLeadMul = 0.5,
	LeadFlowPerBias = 12.0,
	EmergencyThreatRadius = 1800.0,
	EmergencyCommonRadius = 650.0,
	EmergencyAssistMultiplier = 2.0,
	IdleWanderRadius = 130.0,
	IdleWaitBiasGate = 12,
	IdleScoutAlways = true,
	CardRerollInterval = 300.0,
	CardRerollChance = 22,
	EnableActions = true,
	EnableRescue = true,
	EnableRetreat = true,
	EnableCover = true,
	EnableShove = true,
	EnableAssist = true,
	EnableHeal = true,
	ArbiterInterval = 0.18,
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
	"ScoutAheadDistance", "ScoutSideOffset", "ScoutMaxHumanDistance",
	"ScoutMinRetargetDistance", "ScoutRepeatTargetDistance", "ScoutRepeatInterval",
	"ScoutCombatRadius", "ScoutSpecialCombatRadius", "ProgressInterval",
	"ProgressScanRadius", "ProgressMinAdvanceFlow", "ProgressFlowTolerance",
	"ProgressRetargetDistance", "ProgressMaxLeadFlow", "StallProbeExtraFlow",
	"ScoutLeadFlow", "ScoutFlankerLeadMul",
	"LeadFlowPerBias", "IdleWanderRadius", "IdleWaitBiasGate", "IdleScoutAlways",
	"HealDuration", "CombatShoveRadius", "CombatShoveSpecialRadius", "CombatShoveDuration",
	"CombatShoveCooldown", "RetreatHpThreshold", "RetreatCommonCount", "RetreatDuration",
	"RetreatCooldown", "AssistCommonRadius", "AssistCommonCount", "AssistMaxDistance",
	"AssistDuration", "HealCombatRadius", "HealCommonCount",
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
		MaxSeparation = 820,
		EscortCatchupDistance = 640.0,
		ActiveAdvanceDelay = 2.2,
		ActiveAdvanceFlowBoost = 360.0,
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
		ProgressScanRadius = 1050.0,
		ProgressMinAdvanceFlow = 12.0,
		ProgressFlowTolerance = 38.0,
		ProgressRetargetDistance = 80.0,
		ProgressMaxLeadFlow = 980.0,
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
		StallProbeExtraFlow = 520.0,
		ScoutLeadFlow = 400.0,
	},
	escort = {
		label = "escort",
		desc = "0.6.3 human-centered escort behavior",
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
