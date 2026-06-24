// gxLdBot Humanized Bot AI Prototype
// 0.2 aggressive experiment: hotter cvars, impatient profiles, and scout nudges.
// 0.6 card layer: roguelike-style personality cards over flow progress and
// vanilla-first combat.
// 0.6.3 adds emergency defense, stalled-map nudges, and idle micro-movement.
// 0.7 makes "player" the default personality mode: bots act more like another
// active teammate, while "escort" preserves the older human-centered behavior.

if (!("GxLdBot" in getroottable())) {
	::GxLdBot <- {
		Version = "0.7.0-player",
		Debug = false,
		DebugFile = false,
		Initialized = false,
		ThinkEntity = null,
		LastStatusPrint = 0.0,
		Sleeping = false,
		SleepReason = "",
		LastNotice = {},
		LastStallNotice = 0.0,
		LastRoundInit = -999.0,
		LastTeamOrigin = null,
		RoundStartOrigin = null,
		LastTeamMoveTime = 0.0,
		Profiles = {},
		LastTask = {},
		DebugBuffer = [],
		Focus = {},
		Composure = {},
		Claims = {},
		LastSpeak = {},
		LastScout = {},
		LastScoutTarget = {},
		LastAttack = {},
		Cards = {},
		Action = {},
		RetreatCooldownUntil = {},
		ArbiterEntity = null,
		ActionDisabledCleaned = false,
		Reviving = {},
		BeingRevived = {},
		CvarBackup = {},
		StoredCvarDefaults = {},
		CvarDefaultsLoaded = false,
		EmergencyCvarsActive = false,
		ThinkHooks = [],
		RoundHooks = [],
		Settings = {
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
			DebugBufferLimit = 80,
			PersonalLeadMin = 35,
			PersonalLeadMax = 100,
			WaitBiasMin = 0,
			WaitBiasMax = 60,
			ItemCuriosityMin = 30,
			ItemCuriosityMax = 100,
			InteractionBiasMin = 30,
			InteractionBiasMax = 100,
			BaseFollowDistance = 220,
			FollowDistanceJitter = 60,
			MaxSeparation = 620,
			EscortCatchupDistance = 420.0,
			ActiveAdvanceDelay = 6.0,
			ActiveAdvanceFlowBoost = 180.0,
			StallSeconds = 4.0,
			TeamMoveThreshold = 55.0,
			DebugStatusInterval = 5.0,
			RescueDelayMin = 0.25,
			RescueDelayMax = 1.1,
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
			ProgressMinAdvanceFlow = 15.0,
			ProgressFlowTolerance = 50.0,
			ProgressRetargetDistance = 90.0,
			ProgressMaxLeadFlow = 760.0,
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
			EnableRescue = false,
			EnableRetreat = true,
			EnableCover = true,
			EnableShove = true,
			EnableAssist = true,
			EnableHeal = true,
			ArbiterInterval = 0.18,
			RescueShoveRange = 105.0,
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
			HealCommonCount = 3
		}
	};
}

local gxldbotSetSlot = function(tbl, key, value) {
	if (key in tbl) {
		tbl[key] = value;
	} else {
		tbl[key] <- value;
	}
};

gxldbotSetSlot(GxLdBot, "Version", "0.7.0-player");
gxldbotSetSlot(GxLdBot, "Initialized", false);
gxldbotSetSlot(GxLdBot, "Sleeping", false);
gxldbotSetSlot(GxLdBot, "SleepReason", "");
gxldbotSetSlot(GxLdBot, "LastNotice", {});
gxldbotSetSlot(GxLdBot, "LastScoutTarget", {});
gxldbotSetSlot(GxLdBot, "LastAttack", {});
gxldbotSetSlot(GxLdBot, "Cards", {});
gxldbotSetSlot(GxLdBot, "Action", {});
gxldbotSetSlot(GxLdBot, "RetreatCooldownUntil", {});
gxldbotSetSlot(GxLdBot, "ArbiterEntity", null);
gxldbotSetSlot(GxLdBot, "ActionDisabledCleaned", false);
gxldbotSetSlot(GxLdBot, "BTN_SHOVE", 2048);
gxldbotSetSlot(GxLdBot, "BTN_USE", 32);
gxldbotSetSlot(GxLdBot, "Reviving", {});
gxldbotSetSlot(GxLdBot, "BeingRevived", {});
gxldbotSetSlot(GxLdBot, "RoundStartOrigin", null);
if (!("StoredCvarDefaults" in GxLdBot)) {
	GxLdBot.StoredCvarDefaults <- {};
}
gxldbotSetSlot(GxLdBot, "CvarDefaultsLoaded", false);
gxldbotSetSlot(GxLdBot, "EmergencyCvarsActive", false);
gxldbotSetSlot(GxLdBot, "ThinkHooks", []);
gxldbotSetSlot(GxLdBot, "RoundHooks", []);
if (!("Settings" in GxLdBot)) {
	GxLdBot.Settings <- {};
}

local gxldbotDefaultSettings = {
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
	DebugBufferLimit = 80,
	PersonalLeadMin = 35,
	PersonalLeadMax = 100,
	WaitBiasMin = 0,
	WaitBiasMax = 60,
	ItemCuriosityMin = 30,
	ItemCuriosityMax = 100,
	InteractionBiasMin = 30,
	InteractionBiasMax = 100,
	BaseFollowDistance = 220,
	FollowDistanceJitter = 60,
	MaxSeparation = 620,
	EscortCatchupDistance = 420.0,
	ActiveAdvanceDelay = 6.0,
	ActiveAdvanceFlowBoost = 180.0,
	StallSeconds = 4.0,
	TeamMoveThreshold = 55.0,
	DebugStatusInterval = 5.0,
	RescueDelayMin = 0.25,
	RescueDelayMax = 1.1,
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
	ProgressMinAdvanceFlow = 15.0,
	ProgressFlowTolerance = 50.0,
	ProgressRetargetDistance = 90.0,
	ProgressMaxLeadFlow = 760.0,
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
	EnableRescue = false,
	EnableRetreat = true,
	EnableCover = true,
	EnableShove = true,
	EnableAssist = true,
	EnableHeal = true,
	ArbiterInterval = 0.18,
	RescueShoveRange = 105.0,
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
	HealCommonCount = 3
};

foreach (key, value in gxldbotDefaultSettings) {
	gxldbotSetSlot(GxLdBot.Settings, key, value);
}

gxldbotSetSlot(GxLdBot, "ModePresets", {
	player = {
		label = "player",
		desc = "active player-like buddy",
		PersonalLeadMin = 45,
		PersonalLeadMax = 100,
		WaitBiasMin = 0,
		WaitBiasMax = 75,
		ItemCuriosityMin = 45,
		ItemCuriosityMax = 100,
		InteractionBiasMin = 45,
		InteractionBiasMax = 100,
		BaseFollowDistance = 240,
		FollowDistanceJitter = 85,
		MaxSeparation = 820,
		EscortCatchupDistance = 640.0,
		ActiveAdvanceDelay = 2.8,
		ActiveAdvanceFlowBoost = 280.0,
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
		IdleScoutAlways = true
	},
	escort = {
		label = "escort",
		desc = "0.6.3 human-centered escort behavior",
		PersonalLeadMin = 35,
		PersonalLeadMax = 100,
		WaitBiasMin = 0,
		WaitBiasMax = 60,
		ItemCuriosityMin = 30,
		ItemCuriosityMax = 100,
		InteractionBiasMin = 30,
		InteractionBiasMax = 100,
		BaseFollowDistance = 220,
		FollowDistanceJitter = 60,
		MaxSeparation = 620,
		EscortCatchupDistance = 420.0,
		ActiveAdvanceDelay = 6.0,
		ActiveAdvanceFlowBoost = 180.0,
		StallSeconds = 4.0,
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
		ProgressMinAdvanceFlow = 15.0,
		ProgressFlowTolerance = 50.0,
		ProgressRetargetDistance = 90.0,
		ProgressMaxLeadFlow = 760.0,
		LeadFlowPerBias = 12.0,
		IdleWanderRadius = 130.0,
		IdleWaitBiasGate = 12,
		IdleScoutAlways = true
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
		IdleScoutAlways = false
	}
});

gxldbotSetSlot(GxLdBot, "CvarDefaults", {
	sb_friend_immobilized_reaction_time_normal = 0.001,
	sb_friend_immobilized_reaction_time_hard = 0.001,
	sb_friend_immobilized_reaction_time_expert = 0.001,
	sb_friend_immobilized_reaction_time_vs = 0.001,
	sb_allow_leading = 0,
	sb_allow_shoot_through_survivors = 0,
	sb_all_bot_game = 0,
	allow_all_bot_survivor_team = 0,
	sb_max_team_melee_weapons = 1,
	sb_melee_approach_victim = 0,
	sb_toughness_buffer = 40,
	sb_temp_health_consider_factor = 0.75,
	sb_close_checkpoint_door_interval = 0.25,
	sb_battlestation_human_hold_time = 2,
	sb_enforce_proximity_lookat_timeout = 0,
	sb_enforce_proximity_range = 1000,
	sb_follow_stress_factor = 100,
	sb_locomotion_wait_threshold = 2,
	sb_path_lookahead_range = 1000,
	sb_sidestep_for_horde = 1,
	sb_separation_range = 150,
	sb_separation_danger_min_range = 150,
	sb_separation_danger_max_range = 600,
	sb_neighbor_range = 200,
	sb_max_battlestation_range_from_human = 200,
	sb_battlestation_give_up_range_from_human = 500,
	sb_close_threat_range = 250,
	sb_threat_close_range = 250,
	sb_threat_very_close_range = 250,
	sb_threat_medium_range = 500,
	sb_threat_far_range = 1000,
	sb_threat_very_far_range = 2000,
	sb_near_hearing_range = 1000,
	sb_far_hearing_range = 2000,
	sb_combat_saccade_speed = 2000,
	sb_normal_saccade_speed = 350,
	sb_use_button_range = 1000,
	sb_vomit_blind_time = 5,
	survivor_calm_damage_delay = 5,
	survivor_calm_deploy_delay = 2,
	survivor_calm_recent_enemy_delay = 5,
	survivor_calm_weapon_delay = 5
});

gxldbotSetSlot(GxLdBot, "AggressiveCvars", {
	sb_friend_immobilized_reaction_time_normal = 0.001,
	sb_friend_immobilized_reaction_time_hard = 0.001,
	sb_friend_immobilized_reaction_time_expert = 0.001,
	sb_friend_immobilized_reaction_time_vs = 0.001,
	// sb_allow_leading is managed dynamically by UpdateDynamicCvars:
	// off while the team is in the saferoom, on once they move out.
	sb_allow_shoot_through_survivors = 1,
	sb_all_bot_game = 1,
	allow_all_bot_survivor_team = 1,
	sb_max_team_melee_weapons = 2,
	sb_melee_approach_victim = 0,
	sb_toughness_buffer = 300,
	sb_temp_health_consider_factor = 1.00,
	sb_close_checkpoint_door_interval = 0.05,
	sb_battlestation_human_hold_time = 0,
	sb_enforce_proximity_lookat_timeout = 0.0,
	sb_enforce_proximity_range = 520,
	sb_follow_stress_factor = 0,
	sb_locomotion_wait_threshold = 0.0,
	sb_path_lookahead_range = 2800,
	sb_sidestep_for_horde = 1,
	sb_close_threat_range = 450,
	sb_threat_close_range = 450,
	sb_threat_very_close_range = 280,
	sb_threat_medium_range = 900,
	sb_threat_far_range = 3000,
	sb_threat_very_far_range = 5000,
	sb_near_hearing_range = 2400,
	sb_far_hearing_range = 4600,
	sb_combat_saccade_speed = 9999,
	sb_normal_saccade_speed = 4000,
	sb_use_button_range = 1000,
	sb_vomit_blind_time = 0,
	survivor_calm_damage_delay = 0,
	survivor_calm_deploy_delay = 0,
	survivor_calm_recent_enemy_delay = 0,
	survivor_calm_weapon_delay = 0
});

function GxLdBot::Now() {
	try {
		return Time();
	} catch (e) {
		return 0.0;
	}
}

function GxLdBot::Log(msg, force = false) {
	if (!force && !GxLdBot.Debug) {
		return;
	}

	local line = "[gxLdBot] " + msg;

	try {
		printl(line);
	} catch (e) {
	}

	if (GxLdBot.DebugFile || GxLdBot.Settings.EnableDebugFile) {
		GxLdBot.WriteDebugLine(line);
	}
}

function GxLdBot::Chat(player, msg) {
	local plain = "[gxLdBot] " + msg;

	try {
		ClientPrint(player, 5, plain);
		return;
	} catch (e) {
	}

	try {
		printl(plain);
	} catch (e2) {
	}
}

function GxLdBot::ChatAll(msg) {
	local plain = "[gxLdBot] " + msg;
	local sent = false;

	GxLdBot.ForEachSurvivor(function(player) {
		if (GxLdBot.IsBot(player)) {
			return;
		}
		try {
			ClientPrint(player, 5, plain);
			sent = true;
		} catch (e) {
		}
	});

	if (sent) {
		return;
	}

	try {
		ClientPrint(null, 5, plain);
		return;
	} catch (e2) {
	}

	try {
		printl(plain);
	} catch (e3) {
	}
}

function GxLdBot::HumanPlayerCount() {
	local count = 0;
	local player = null;
	while (player = Entities.FindByClassname(player, "player")) {
		if (!GxLdBot.IsBot(player)) {
			count++;
		}
	}
	return count;
}

function GxLdBot::IsMultiplayerActive() {
	if (!GxLdBot.Settings.EnableMultiplayerGuard) {
		return false;
	}
	return GxLdBot.HumanPlayerCount() > 1;
}

function GxLdBot::Notify(key, msg, cooldown = 0.0) {
	if (!GxLdBot.Settings.EnableChatEvents) {
		return;
	}
	if (key.len() >= 7 && key.slice(0, 7) == "action:" && !GxLdBot.Debug) {
		return;
	}
	// Do not broadcast experimental bot debug text into real multiplayer.
	if (GxLdBot.IsMultiplayerActive()) {
		return;
	}

	local now = GxLdBot.Now();
	if (cooldown > 0.0 && key in GxLdBot.LastNotice &&
			(now - GxLdBot.LastNotice[key]) < cooldown) {
		return;
	}
	GxLdBot.SetTableSlot(GxLdBot.LastNotice, key, now);
	GxLdBot.ChatAll(msg);
}

function GxLdBot::SetSleeping(value, reason) {
	if (GxLdBot.Sleeping == value && GxLdBot.SleepReason == reason) {
		return;
	}
	GxLdBot.Sleeping = value;
	GxLdBot.SleepReason = value ? reason : "";

	if (value) {
		if ("ClearAllActions" in GxLdBot) {
			GxLdBot.ClearAllActions(true);
		}
		GxLdBot.RestoreMildCvars();
		GxLdBot.Log("sleeping: " + reason, true);
		return;
	}

	GxLdBot.Log("woke from sleep guard", true);
	if ("StartArbiterThink" in GxLdBot) {
		GxLdBot.StartArbiterThink();
	}
	GxLdBot.Notify("wake", "woke up: single-player bot control active", 10.0);
}

function GxLdBot::UpdateSleepState() {
	if (GxLdBot.Settings.EnableMultiplayerGuard && GxLdBot.HumanPlayerCount() > 1) {
		GxLdBot.SetSleeping(true, "multiplayer humans detected");
		return true;
	}
	if (GxLdBot.Sleeping) {
		GxLdBot.SetSleeping(false, "");
	}
	return false;
}

function GxLdBot::WriteDebugLine(line) {
	try {
		if (!("DebugBuffer" in GxLdBot)) {
			GxLdBot.DebugBuffer <- [];
		}

		GxLdBot.DebugBuffer.append(GxLdBot.Now().tostring() + " " + line);

		local limit = GxLdBot.Settings.DebugBufferLimit;
		while (GxLdBot.DebugBuffer.len() > limit) {
			GxLdBot.DebugBuffer.remove(0);
		}

		local output = "";
		foreach (idx, item in GxLdBot.DebugBuffer) {
			output += item + "\n";
		}

		StringToFile("gxldbot/debug.txt", output);
	} catch (e) {
	}
}

function GxLdBot::RandFloat(minValue, maxValue) {
	try {
		return RandomFloat(minValue, maxValue);
	} catch (e) {
		return minValue;
	}
}

function GxLdBot::RandInt(minValue, maxValue) {
	local value = GxLdBot.RandFloat(minValue.tofloat(), (maxValue + 1).tofloat()).tointeger();
	if (value < minValue) {
		return minValue;
	}
	if (value > maxValue) {
		return maxValue;
	}
	return value;
}

// Run fn inside a guard so one module's failure can never abort the think loop.
function GxLdBot::SafeCall(label, fn) {
	try {
		return fn();
	} catch (e) {
		GxLdBot.Log("SafeCall " + label + " failed: " + e, true);
		return null;
	}
}

function GxLdBot::SetTableSlot(tbl, key, value) {
	if (key in tbl) {
		tbl[key] = value;
	} else {
		tbl[key] <- value;
	}
}

function GxLdBot::NormalizeModeName(mode) {
	if (mode == null) {
		return null;
	}
	local m = mode.tolower();
	if (m == "buddy" || m == "pub" || m == "human" || m == "humanlike") {
		return "player";
	}
	if (m == "old" || m == "classic" || m == "legacy" || m == "teammate") {
		return "escort";
	}
	if (m == "debug" || m == "conservative") {
		return "safe";
	}
	return m;
}

function GxLdBot::ApplyMode(mode, announce = false, player = null) {
	local normalized = GxLdBot.NormalizeModeName(mode);
	if (normalized == null || !(normalized in GxLdBot.ModePresets)) {
		if (announce) {
			GxLdBot.Chat(player, "mode options: player escort safe");
		}
		return false;
	}

	local preset = GxLdBot.ModePresets[normalized];
	GxLdBot.Settings.Mode = normalized;
	foreach (key, value in preset) {
		if (key == "label" || key == "desc") {
			continue;
		}
		GxLdBot.SetTableSlot(GxLdBot.Settings, key, value);
	}

	GxLdBot.LastScout = {};
	GxLdBot.LastScoutTarget = {};
	if ("ClearAllActions" in GxLdBot) {
		GxLdBot.ClearAllActions(true);
	}
	if ("ApplyRoleMode" in GxLdBot) {
		GxLdBot.ApplyRoleMode();
	}
	if ("AssignRoles" in GxLdBot) {
		GxLdBot.AssignRoles();
	}
	if (GxLdBot.Settings.EnableMildCvars && !GxLdBot.Sleeping) {
		GxLdBot.ApplyMildCvars();
		if ("ApplyTeamSpacing" in GxLdBot) {
			GxLdBot.ApplyTeamSpacing();
		}
	}

	local desc = ("desc" in preset) ? preset.desc : normalized;
	GxLdBot.Log("mode=" + normalized + " " + desc, true);
	if (announce) {
		GxLdBot.Chat(player, "mode=" + normalized + " (" + desc + ")");
		if (normalized == "escort") {
			GxLdBot.Chat(player, "escort is the old 0.6.3-style behavior");
		}
	}
	return true;
}

function GxLdBot::PrintMode(player) {
	local mode = ("Mode" in GxLdBot.Settings) ? GxLdBot.Settings.Mode : "player";
	local desc = mode;
	if (mode in GxLdBot.ModePresets && "desc" in GxLdBot.ModePresets[mode]) {
		desc = GxLdBot.ModePresets[mode].desc;
	}
	GxLdBot.Chat(player, "mode=" + mode + " (" + desc + ")");
	GxLdBot.Chat(player, "switch: !hbot_mode player | escort | safe");
	GxLdBot.Chat(player, "console: scripted_user_func hbot_mode_player / hbot_mode_escort");
}

function GxLdBot::GetProfile(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return null;
	}
	local idx = player.GetEntityIndex();
	if (idx in GxLdBot.Profiles) {
		return GxLdBot.Profiles[idx];
	}
	return null;
}

function GxLdBot::DistanceBetween(a, b) {
	if (!GxLdBot.IsValidEntity(a) || !GxLdBot.IsValidEntity(b)) {
		return 999999.0;
	}
	try {
		return (a.GetOrigin() - b.GetOrigin()).Length();
	} catch (e) {
		return 999999.0;
	}
}

// Closest alive human survivor to the given entity, or null.
function GxLdBot::NearestHuman(toEnt) {
	local best = null;
	local bestDist = 999999.0;
	GxLdBot.ForEachSurvivor(function(p) {
		if (GxLdBot.IsBot(p) || !GxLdBot.IsAlive(p)) {
			return;
		}
		local d = GxLdBot.DistanceBetween(toEnt, p);
		if (d < bestDist) {
			bestDist = d;
			best = p;
		}
	});
	return best;
}

function GxLdBot::HasAliveHuman() {
	local found = false;
	GxLdBot.ForEachSurvivor(function(player) {
		if (!found && GxLdBot.IsAlive(player) && !GxLdBot.IsBot(player)) {
			found = true;
		}
	});
	return found;
}

function GxLdBot::SafeName(player) {
	if (player == null) {
		return "null";
	}

	try {
		return player.GetPlayerName();
	} catch (e) {
	}

	try {
		return player.GetName();
	} catch (e2) {
	}

	try {
		return "player#" + player.GetEntityIndex().tostring();
	} catch (e3) {
	}

	return "player";
}

function GxLdBot::IsValidEntity(ent) {
	if (ent == null) {
		return false;
	}

	try {
		return ent.IsValid();
	} catch (e) {
		return false;
	}
}

function GxLdBot::IsSurvivor(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return false;
	}

	try {
		return player.IsSurvivor();
	} catch (e) {
	}

	try {
		return NetProps.GetPropInt(player, "m_iTeamNum") == 2;
	} catch (e2) {
	}

	return false;
}

function GxLdBot::IsAlive(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return false;
	}

	try {
		if (player.IsDead()) {
			return false;
		}
	} catch (e) {
	}

	return true;
}

function GxLdBot::IsBot(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return false;
	}

	try {
		return IsPlayerABot(player);
	} catch (e) {
	}

	return false;
}

function GxLdBot::ForEachSurvivor(callback) {
	local player = null;
	while (player = Entities.FindByClassname(player, "player")) {
		if (GxLdBot.IsSurvivor(player)) {
			callback(player);
		}
	}
}

function GxLdBot::ForEachSurvivorBot(callback) {
	GxLdBot.ForEachSurvivor(function(player) {
		if (GxLdBot.IsBot(player)) {
			callback(player);
		}
	});
}

function GxLdBot::MakeProfile(player) {
	local followBase = GxLdBot.Settings.BaseFollowDistance;
	local followJitter = GxLdBot.Settings.FollowDistanceJitter;
	local leadMin = ("PersonalLeadMin" in GxLdBot.Settings) ? GxLdBot.Settings.PersonalLeadMin : 35;
	local leadMax = ("PersonalLeadMax" in GxLdBot.Settings) ? GxLdBot.Settings.PersonalLeadMax : 100;
	local waitMin = ("WaitBiasMin" in GxLdBot.Settings) ? GxLdBot.Settings.WaitBiasMin : 0;
	local waitMax = ("WaitBiasMax" in GxLdBot.Settings) ? GxLdBot.Settings.WaitBiasMax : 60;
	local itemMin = ("ItemCuriosityMin" in GxLdBot.Settings) ? GxLdBot.Settings.ItemCuriosityMin : 30;
	local itemMax = ("ItemCuriosityMax" in GxLdBot.Settings) ? GxLdBot.Settings.ItemCuriosityMax : 100;
	local interactMin = ("InteractionBiasMin" in GxLdBot.Settings) ? GxLdBot.Settings.InteractionBiasMin : 30;
	local interactMax = ("InteractionBiasMax" in GxLdBot.Settings) ? GxLdBot.Settings.InteractionBiasMax : 100;

	local profile = {
		name = GxLdBot.SafeName(player),
		role = "follower",
		// Wider personality spread so bots feel like different players, not
		// clones. Kept strong enough to carry, but with real variance: a
		// jumpy rookie and a calm veteran should behave visibly differently.
		reaction = GxLdBot.RandFloat(0.15, 0.70),
		rescueBias = GxLdBot.RandInt(55, 100),
		followDistance = followBase,
		personalLeadBias = GxLdBot.RandInt(leadMin, leadMax),
		leadBias = 60,
		personalFollowOffset = GxLdBot.RandInt(-followJitter, followJitter),
		itemCuriosity = GxLdBot.RandInt(itemMin, itemMax),
		throwableBias = GxLdBot.RandInt(40, 100),
		waitBias = GxLdBot.RandInt(waitMin, waitMax),
		interactionBias = GxLdBot.RandInt(interactMin, interactMax),
		composureBase = GxLdBot.RandInt(55, 100),
		healThreshold = GxLdBot.RandInt(12, 45),
		letItemBias = GxLdBot.RandInt(0, 60)
	};

	profile.followDistance = followBase + profile.personalFollowOffset;
	if (profile.followDistance < 140) {
		profile.followDistance = 140;
	}

	return profile;
}

function GxLdBot::ClearBotState(idx) {
	if (idx in GxLdBot.Profiles) {
		delete GxLdBot.Profiles[idx];
	}
	if (idx in GxLdBot.Focus) {
		delete GxLdBot.Focus[idx];
	}
	if (idx in GxLdBot.Composure) {
		delete GxLdBot.Composure[idx];
	}
	if (idx in GxLdBot.LastSpeak) {
		delete GxLdBot.LastSpeak[idx];
	}
	if (idx in GxLdBot.LastScout) {
		delete GxLdBot.LastScout[idx];
	}
	if (idx in GxLdBot.LastScoutTarget) {
		delete GxLdBot.LastScoutTarget[idx];
	}
	if (idx in GxLdBot.LastAttack) {
		delete GxLdBot.LastAttack[idx];
	}
	if ("Cards" in GxLdBot && idx in GxLdBot.Cards) {
		delete GxLdBot.Cards[idx];
	}
	if ("Action" in GxLdBot && idx in GxLdBot.Action) {
		delete GxLdBot.Action[idx];
	}
	if ("RetreatCooldownUntil" in GxLdBot && idx in GxLdBot.RetreatCooldownUntil) {
		delete GxLdBot.RetreatCooldownUntil[idx];
	}
	if (idx in GxLdBot.Reviving) {
		delete GxLdBot.Reviving[idx];
	}
	if (idx in GxLdBot.BeingRevived) {
		delete GxLdBot.BeingRevived[idx];
	}
	if (idx in GxLdBot.LastTask) {
		delete GxLdBot.LastTask[idx];
	}
	if ("HealIntent" in GxLdBot && idx in GxLdBot.HealIntent) {
		delete GxLdBot.HealIntent[idx];
	}

	local deadClaims = [];
	foreach (key, claim in GxLdBot.Claims) {
		try {
			if (claim.owner == idx) {
				deadClaims.append(key);
			}
		} catch (e) {
		}
	}
	foreach (i, key in deadClaims) {
		delete GxLdBot.Claims[key];
	}
}

function GxLdBot::EnsureProfiles(force = false) {
	if (!GxLdBot.Settings.EnableProfiles) {
		return;
	}
	if (GxLdBot.UpdateSleepState()) {
		return;
	}

	local added = false;
	local removed = false;
	local current = {};
	GxLdBot.ForEachSurvivorBot(function(player) {
		local idx = player.GetEntityIndex();
		current[idx] <- true;
		if (force || !(idx in GxLdBot.Profiles)) {
			GxLdBot.Profiles[idx] <- GxLdBot.MakeProfile(player);
			added = true;
			local p = GxLdBot.Profiles[idx];
			GxLdBot.Log("profile " + p.name +
				" reaction=" + p.reaction +
				" rescue=" + p.rescueBias +
				" follow=" + p.followDistance +
				" lead=" + p.leadBias +
				" item=" + p.itemCuriosity +
				" throwable=" + p.throwableBias +
				" wait=" + p.waitBias +
				" heal=" + p.healThreshold +
				" composure=" + p.composureBase, true);
		}
	});

	local stale = [];
	foreach (idx, profile in GxLdBot.Profiles) {
		if (!(idx in current)) {
			stale.append(idx);
		}
	}
	foreach (i, idx in stale) {
		GxLdBot.ClearBotState(idx);
		removed = true;
		GxLdBot.Log("cleared stale bot state idx=" + idx, true);
	}

	// If any new bot profile appeared (late spawn, takeover, !hbot_regen),
	// or any old bot profile disappeared, rebalance roles so nobody is stuck
	// on the default follower or counted with stale spacing.
	if ((added || removed) && ("AssignRoles" in GxLdBot)) {
		GxLdBot.AssignRoles();
	}
}

function GxLdBot::ApplyMildCvars() {
	if (!GxLdBot.Settings.EnableMildCvars) {
		GxLdBot.Log("aggressive cvars disabled", true);
		return;
	}
	if (GxLdBot.Sleeping || GxLdBot.UpdateSleepState()) {
		GxLdBot.Log("aggressive cvars skipped: sleep guard active", true);
		return;
	}

	foreach (name, value in GxLdBot.AggressiveCvars) {
		GxLdBot.TrackedSetCvar(name, value);
	}

	GxLdBot.Log("applied aggressive bot cvars", true);
}

function GxLdBot::LoadStoredCvarDefaults() {
	if (GxLdBot.CvarDefaultsLoaded) {
		return;
	}
	GxLdBot.CvarDefaultsLoaded = true;
	try {
		local text = FileToString("gxldbot/cvars.txt");
		if (text == null || text.len() <= 0) {
			return;
		}
		local lines = split(text, "\r\n");
		foreach (i, line in lines) {
			if (line == null || line.len() <= 0) {
				continue;
			}
			local eq = line.find("=");
			if (eq == null || eq <= 0) {
				continue;
			}
			local name = line.slice(0, eq);
			local value = line.slice(eq + 1).tofloat();
			if (name in GxLdBot.StoredCvarDefaults) {
				GxLdBot.StoredCvarDefaults[name] = value;
			} else {
				GxLdBot.StoredCvarDefaults[name] <- value;
			}
		}
	} catch (e) {
	}
}

function GxLdBot::SaveStoredCvarDefaults() {
	try {
		local output = "";
		foreach (name, value in GxLdBot.StoredCvarDefaults) {
			output += name + "=" + value + "\n";
		}
		StringToFile("gxldbot/cvars.txt", output);
	} catch (e) {
	}
}

function GxLdBot::RememberCvarDefault(name) {
	GxLdBot.LoadStoredCvarDefaults();
	if (name in GxLdBot.StoredCvarDefaults) {
		return;
	}
	try {
		local value = Convars.GetFloat(name);
		if (name in GxLdBot.StoredCvarDefaults) {
			GxLdBot.StoredCvarDefaults[name] = value;
		} else {
			GxLdBot.StoredCvarDefaults[name] <- value;
		}
		GxLdBot.SaveStoredCvarDefaults();
	} catch (e) {
	}
}

// Restore every cvar we changed. Prefer file-backed defaults captured before
// the first gxLdBot write so a map transition cannot snapshot our previous
// aggressive values as "original".
function GxLdBot::RestoreMildCvars() {
	GxLdBot.LoadStoredCvarDefaults();
	foreach (name, original in GxLdBot.CvarBackup) {
		try {
			local value = (name in GxLdBot.StoredCvarDefaults)
				? GxLdBot.StoredCvarDefaults[name]
				: ((name in GxLdBot.CvarDefaults) ? GxLdBot.CvarDefaults[name] : original);
			Convars.SetValue(name, value);
		} catch (e) {
			GxLdBot.Log("failed to restore cvar " + name + ": " + e, true);
		}
	}
	GxLdBot.CvarBackup = {};
	GxLdBot.Log("restored aggressive bot cvars", true);
}

// Set a cvar while snapshotting its original, so RestoreMildCvars can undo it.
// Modules should use this instead of Convars.SetValue for any bot tuning.
function GxLdBot::TrackedSetCvar(name, value) {
	try {
		GxLdBot.RememberCvarDefault(name);
		if (!(name in GxLdBot.CvarBackup)) {
			GxLdBot.CvarBackup[name] <- Convars.GetFloat(name);
		}
		Convars.SetValue(name, value);
	} catch (e) {
		GxLdBot.Log("TrackedSetCvar " + name + " failed: " + e, true);
	}
}

// True once any survivor has stepped out of the start saferoom. Until then we
// suppress forward pressure (scouting + leading) so bots don't bolt the door
// before the human even moves.
function GxLdBot::TeamHasLeftSafeArea() {
	try {
		return Director.HasAnySurvivorLeftSafeArea();
	} catch (e) {
	}
	// Fallback if the Director call is unavailable: "left" == nobody is still
	// flagged as inside the mission start area.
	local inStart = false;
	GxLdBot.ForEachSurvivor(function(s) {
		if (GxLdBot.BotInStartArea(s)) {
			inStart = true;
		}
	});
	return inStart ? false : GxLdBot.TeamMovedSinceRoundStart();
}

// Is this survivor still inside the mission start area (the opening saferoom)?
// Per-bot guard so an individual bot is never pushed forward while still inside.
function GxLdBot::BotInStartArea(ent) {
	if (!GxLdBot.IsValidEntity(ent)) {
		return false;
	}
	try {
		return NetProps.GetPropBool(ent, "m_isInMissionStartArea");
	} catch (e) {
	}
	try {
		return NetProps.GetPropInt(ent, "m_isInMissionStartArea") != 0;
	} catch (e2) {
	}
	return false;
}

function GxLdBot::TeamMovedSinceRoundStart() {
	if (GxLdBot.RoundStartOrigin == null) {
		return false;
	}
	try {
		return (GxLdBot.TeamCentroid() - GxLdBot.RoundStartOrigin).Length() >
			GxLdBot.Settings.TeamMoveThreshold;
	} catch (e) {
		return false;
	}
}

// Cvars whose value should track the safe-area state. Leading is off while the
// team is still in the saferoom, on once they move out. Goes through
// TrackedSetCvar so toggling cvars off still restores the original value.
function GxLdBot::UpdateDynamicCvars() {
	if (!GxLdBot.Settings.EnableMildCvars) {
		return;
	}
	local canLead = (!GxLdBot.HasAliveHuman()) || GxLdBot.TeamHasLeftSafeArea();
	GxLdBot.TrackedSetCvar("sb_allow_leading", canLead ? 1 : 0);
	local emergency = ("TeamEmergency" in GxLdBot) && GxLdBot.TeamEmergency();
	if (emergency) {
		GxLdBot.EmergencyCvarsActive = true;
		GxLdBot.TrackedSetCvar("sb_threat_far_range", 6000);
		GxLdBot.TrackedSetCvar("sb_threat_very_far_range", 9000);
		GxLdBot.TrackedSetCvar("sb_near_hearing_range", 5000);
		GxLdBot.TrackedSetCvar("sb_far_hearing_range", 9000);
		GxLdBot.TrackedSetCvar("sb_combat_saccade_speed", 9999);
		GxLdBot.TrackedSetCvar("sb_normal_saccade_speed", 9999);
		GxLdBot.TrackedSetCvar("sb_separation_range", 90);
		GxLdBot.TrackedSetCvar("sb_neighbor_range", 140);
		return;
	}
	if (GxLdBot.EmergencyCvarsActive) {
		GxLdBot.EmergencyCvarsActive = false;
		GxLdBot.ApplyMildCvars();
		if ("ApplyTeamSpacing" in GxLdBot) {
			GxLdBot.ApplyTeamSpacing();
		}
	}
}

function GxLdBot::TeamCentroid() {
	local count = 0;
	local sum = Vector(0, 0, 0);

	GxLdBot.ForEachSurvivor(function(player) {
		if (GxLdBot.IsAlive(player)) {
			try {
				sum = sum + player.GetOrigin();
				count++;
			} catch (e) {
			}
		}
	});

	if (count <= 0) {
		return null;
	}

	return sum.Scale(1.0 / count.tofloat());
}

function GxLdBot::HumanCentroid() {
	local count = 0;
	local sum = Vector(0, 0, 0);

	GxLdBot.ForEachSurvivor(function(player) {
		if (GxLdBot.IsAlive(player) && !GxLdBot.IsBot(player)) {
			try {
				sum = sum + player.GetOrigin();
				count++;
			} catch (e) {
			}
		}
	});

	if (count <= 0) {
		return null;
	}

	return sum.Scale(1.0 / count.tofloat());
}

function GxLdBot::ObserveTeamMovement() {
	if (!GxLdBot.Settings.EnableObservation) {
		return;
	}

	local now = GxLdBot.Now();
	local origin = GxLdBot.HumanCentroid();
	if (origin == null) {
		origin = GxLdBot.TeamCentroid();
	}
	if (origin == null) {
		return;
	}

	if (GxLdBot.LastTeamOrigin == null) {
		GxLdBot.LastTeamOrigin = origin;
		if (GxLdBot.RoundStartOrigin == null) {
			GxLdBot.RoundStartOrigin = origin;
		}
		GxLdBot.LastTeamMoveTime = now;
		return;
	}

	local moved = (origin - GxLdBot.LastTeamOrigin).Length();
	if (moved >= GxLdBot.Settings.TeamMoveThreshold) {
		GxLdBot.LastTeamOrigin = origin;
		GxLdBot.LastTeamMoveTime = now;
		return;
	}

	local stalledFor = now - GxLdBot.LastTeamMoveTime;
	if (stalledFor >= GxLdBot.Settings.StallSeconds && now - GxLdBot.LastStallNotice > 8.0) {
		GxLdBot.LastStallNotice = now;
		GxLdBot.Log("team_stalled duration=" + stalledFor + " moved=" + moved);
	}
}

function GxLdBot::PrintProfiles(player) {
	GxLdBot.EnsureProfiles(false);

	local printed = false;
	foreach (idx, p in GxLdBot.Profiles) {
		printed = true;
		GxLdBot.Chat(player, p.name +
			" reaction=" + p.reaction +
			" rescue=" + p.rescueBias +
			" follow=" + p.followDistance +
			" lead=" + p.leadBias +
			" card=" + (("cardName" in p) ? p.cardName : "None") +
			" item=" + p.itemCuriosity +
			" throwable=" + p.throwableBias +
			" wait=" + p.waitBias);
	}

	if (!printed) {
		GxLdBot.Chat(player, "no survivor bot profiles yet");
	}
}

function GxLdBot::PrintStatus(player) {
	local botCount = 0;
	local humanCount = 0;

	GxLdBot.ForEachSurvivor(function(p) {
		if (GxLdBot.IsBot(p)) {
			botCount++;
		} else {
			humanCount++;
		}
	});

	GxLdBot.Chat(player, "v" + GxLdBot.Version +
		" mode=" + GxLdBot.Settings.Mode +
		" debug=" + GxLdBot.Debug +
		" debugFile=" + (GxLdBot.DebugFile || GxLdBot.Settings.EnableDebugFile) +
		" bots=" + botCount +
		" humans=" + humanCount +
		" sleep=" + GxLdBot.Sleeping +
		" chat=" + GxLdBot.Settings.EnableChatEvents +
		" mpGuard=" + GxLdBot.Settings.EnableMultiplayerGuard +
		" cvars=" + GxLdBot.Settings.EnableMildCvars +
		" cards=" + GxLdBot.Settings.EnableCards +
		" scout=" + GxLdBot.Settings.EnableScout +
		" progress=" + GxLdBot.Settings.EnableProgress +
		" actions=" + GxLdBot.Settings.EnableActions +
		" rescue=" + GxLdBot.Settings.EnableRescue +
		" retreat=" + GxLdBot.Settings.EnableRetreat +
		" cover=" + GxLdBot.Settings.EnableCover +
		" shove=" + GxLdBot.Settings.EnableShove +
		" assist=" + GxLdBot.Settings.EnableAssist);
}

function GxLdBot::NormalizeCommandText(text) {
	if (text == null) {
		return "";
	}

	local cmd = text.tolower();
	if (cmd.len() <= 0) {
		return cmd;
	}

	if (cmd.slice(0, 1) == "!") {
		return cmd;
	}

	if (cmd.find("hbot_") == 0) {
		return "!" + cmd;
	}

	return cmd;
}

function GxLdBot::HandleCommand(player, text) {
	text = GxLdBot.NormalizeCommandText(text);

	if (text == "!hbot_debug") {
		GxLdBot.Debug = !GxLdBot.Debug;
		GxLdBot.Chat(player, "debug=" + GxLdBot.Debug);
		GxLdBot.Log("debug toggled by " + GxLdBot.SafeName(player), true);
		return true;
	}

	if (text == "!hbot_debugfile") {
		GxLdBot.DebugFile = !GxLdBot.DebugFile;
		GxLdBot.Chat(player, "debugFile=" + GxLdBot.DebugFile);
		GxLdBot.Log("debug file toggled by " + GxLdBot.SafeName(player), true);
		return true;
	}

	if (text == "!hbot_chat") {
		GxLdBot.Settings.EnableChatEvents = !GxLdBot.Settings.EnableChatEvents;
		GxLdBot.Chat(player, "chat=" + GxLdBot.Settings.EnableChatEvents);
		return true;
	}

	if (text == "!hbot_mpguard") {
		GxLdBot.Settings.EnableMultiplayerGuard = !GxLdBot.Settings.EnableMultiplayerGuard;
		GxLdBot.UpdateSleepState();
		GxLdBot.Chat(player, "mpGuard=" + GxLdBot.Settings.EnableMultiplayerGuard +
			" sleep=" + GxLdBot.Sleeping);
		return true;
	}

	if (text == "!hbot_status") {
		GxLdBot.PrintStatus(player);
		return true;
	}

	if (text == "!hbot_mode") {
		GxLdBot.PrintMode(player);
		return true;
	}

	if (text.find("!hbot_mode ") == 0) {
		GxLdBot.ApplyMode(text.slice(11), true, player);
		return true;
	}

	if (text == "!hbot_mode_player" || text == "!hbot_player" || text == "!hbot_buddy") {
		GxLdBot.ApplyMode("player", true, player);
		return true;
	}

	if (text == "!hbot_mode_escort" || text == "!hbot_old" || text == "!hbot_legacy") {
		GxLdBot.ApplyMode("escort", true, player);
		return true;
	}

	if (text == "!hbot_mode_safe" || text == "!hbot_safe") {
		GxLdBot.ApplyMode("safe", true, player);
		return true;
	}

	if (text == "!hbot_profile") {
		GxLdBot.PrintProfiles(player);
		return true;
	}

	if (text == "!hbot_regen") {
		GxLdBot.Profiles = {};
		GxLdBot.Cards = {};
		GxLdBot.EnsureProfiles(true);
		GxLdBot.Chat(player, "profiles regenerated");
		return true;
	}

	if (text == "!hbot_cvars") {
		GxLdBot.Settings.EnableMildCvars = !GxLdBot.Settings.EnableMildCvars;
		if (GxLdBot.Settings.EnableMildCvars) {
			GxLdBot.ApplyMildCvars();
			if ("ApplyTeamSpacing" in GxLdBot) {
				GxLdBot.ApplyTeamSpacing();
			}
		} else {
			GxLdBot.RestoreMildCvars();
		}
		GxLdBot.Chat(player, "cvars=" + GxLdBot.Settings.EnableMildCvars);
		return true;
	}

	if (text == "!hbot_scout") {
		GxLdBot.Settings.EnableScout = !GxLdBot.Settings.EnableScout;
		GxLdBot.Chat(player, "scout=" + GxLdBot.Settings.EnableScout);
		return true;
	}

	if (text == "!hbot_cards_toggle") {
		GxLdBot.Settings.EnableCards = !GxLdBot.Settings.EnableCards;
		if ("AssignRoles" in GxLdBot) {
			GxLdBot.AssignRoles();
		}
		GxLdBot.Chat(player, "cards=" + GxLdBot.Settings.EnableCards);
		return true;
	}

	if (text == "!hbot_cards") {
		GxLdBot.SafeCall("cmd_cards", function() {
			if (!("PrintCards" in GxLdBot)) {
				try {
					IncludeScript("gxldbot/cards");
				} catch (e) {
					GxLdBot.Log("include cards retry failed: " + e, true);
				}
			}
			if ("PrintCards" in GxLdBot) {
				GxLdBot.PrintCards(player);
			} else {
				GxLdBot.Chat(player, "cards module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_reroll_cards") {
		GxLdBot.SafeCall("cmd_reroll_cards", function() {
			if (!("RerollAllCards" in GxLdBot)) {
				try {
					IncludeScript("gxldbot/cards");
				} catch (e) {
					GxLdBot.Log("include cards retry failed: " + e, true);
				}
			}
			if ("RerollAllCards" in GxLdBot) {
				GxLdBot.RerollAllCards("command");
				GxLdBot.Chat(player, "cards rerolled");
			} else {
				GxLdBot.Chat(player, "cards module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_progress") {
		GxLdBot.Settings.EnableProgress = !GxLdBot.Settings.EnableProgress;
		GxLdBot.Chat(player, "progress=" + GxLdBot.Settings.EnableProgress);
		return true;
	}

	if (text == "!hbot_progress_status") {
		GxLdBot.SafeCall("cmd_progress", function() {
			if (!("PrintProgress" in GxLdBot)) {
				try {
					IncludeScript("gxldbot/progress");
				} catch (e) {
					GxLdBot.Log("include progress retry failed: " + e, true);
				}
			}
			if ("PrintProgress" in GxLdBot) {
				GxLdBot.PrintProgress(player);
			} else {
				GxLdBot.Chat(player, "progress module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_actions_toggle") {
		GxLdBot.Settings.EnableActions = !GxLdBot.Settings.EnableActions;
		if (!GxLdBot.Settings.EnableActions && "ClearAllActions" in GxLdBot) {
			GxLdBot.ClearAllActions(true);
			GxLdBot.ActionDisabledCleaned = true;
		}
		GxLdBot.Chat(player, "actions=" + GxLdBot.Settings.EnableActions);
		return true;
	}

	if (text == "!hbot_rescue") {
		GxLdBot.Settings.EnableRescue = !GxLdBot.Settings.EnableRescue;
		GxLdBot.Chat(player, "rescue=" + GxLdBot.Settings.EnableRescue);
		return true;
	}

	if (text == "!hbot_retreat") {
		GxLdBot.Settings.EnableRetreat = !GxLdBot.Settings.EnableRetreat;
		GxLdBot.Chat(player, "retreat=" + GxLdBot.Settings.EnableRetreat);
		return true;
	}

	if (text == "!hbot_cover") {
		GxLdBot.Settings.EnableCover = !GxLdBot.Settings.EnableCover;
		GxLdBot.Chat(player, "cover=" + GxLdBot.Settings.EnableCover);
		return true;
	}

	if (text == "!hbot_shove") {
		GxLdBot.Settings.EnableShove = !GxLdBot.Settings.EnableShove;
		GxLdBot.Chat(player, "shove=" + GxLdBot.Settings.EnableShove);
		return true;
	}

	if (text == "!hbot_assist") {
		GxLdBot.Settings.EnableAssist = !GxLdBot.Settings.EnableAssist;
		GxLdBot.Chat(player, "assist=" + GxLdBot.Settings.EnableAssist);
		return true;
	}

	if (text == "!hbot_actions") {
		GxLdBot.SafeCall("cmd_actions", function() {
			if (!("PrintActions" in GxLdBot)) {
				try {
					IncludeScript("gxldbot/actions");
				} catch (e) {
					GxLdBot.Log("include actions retry failed: " + e, true);
				}
			}
			if ("PrintActions" in GxLdBot) {
				GxLdBot.PrintActions(player);
			} else {
				GxLdBot.Chat(player, "actions module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_roles") {
		GxLdBot.SafeCall("cmd_roles", function() {
			if ("PrintRoles" in GxLdBot) {
				GxLdBot.PrintRoles(player);
			} else {
				GxLdBot.Chat(player, "roles module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_focus") {
		GxLdBot.SafeCall("cmd_focus", function() {
			if ("PrintFocus" in GxLdBot) {
				GxLdBot.PrintFocus(player);
			} else {
				GxLdBot.Chat(player, "focus module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_claims") {
		GxLdBot.SafeCall("cmd_claims", function() {
			if ("PrintClaims" in GxLdBot) {
				GxLdBot.PrintClaims(player);
			} else {
				GxLdBot.Chat(player, "claims module not loaded");
			}
		});
		return true;
	}

	if (text == "!hbot_help") {
		GxLdBot.Chat(player, "!hbot_debug !hbot_debugfile !hbot_chat !hbot_mpguard !hbot_status !hbot_mode !hbot_profile !hbot_regen");
		GxLdBot.Chat(player, "!hbot_mode player|escort|safe  console: hbot_mode_player / hbot_mode_escort");
		GxLdBot.Chat(player, "!hbot_cvars !hbot_scout");
		GxLdBot.Chat(player, "!hbot_actions !hbot_actions_toggle !hbot_rescue !hbot_retreat !hbot_cover !hbot_shove !hbot_assist");
		GxLdBot.Chat(player, "!hbot_progress !hbot_progress_status !hbot_cards !hbot_reroll_cards !hbot_cards_toggle");
		GxLdBot.Chat(player, "!hbot_roles !hbot_focus !hbot_claims");
		return true;
	}

	return false;
}

function GxLdBot::OnConsoleCommand(player, arg) {
	local text = GxLdBot.NormalizeCommandText(arg);
	if (text.len() <= 0) {
		GxLdBot.Chat(player, "usage: scripted_user_func hbot_status");
		return true;
	}

	if (!GxLdBot.HandleCommand(player, text)) {
		return false;
	}

	return true;
}

function GxLdBot::OnPlayerSay(event) {
	if (!("text" in event)) {
		return;
	}

	local text = event.text;
	if (text == null || text.len() <= 0) {
		return;
	}

	if (text.slice(0, 1) != "!") {
		return;
	}

	local player = null;
	try {
		player = GetPlayerFromUserID(event.userid);
	} catch (e) {
	}

	GxLdBot.HandleCommand(player, text);
}

function GxLdBot::PlayerFromEvent(event, field) {
	if (!(field in event)) {
		return null;
	}
	try {
		return GetPlayerFromUserID(event[field]);
	} catch (e) {
		return null;
	}
}

function GxLdBot::SetReviveState(reviver, subject) {
	if (!GxLdBot.IsValidEntity(reviver) || !GxLdBot.IsValidEntity(subject)) {
		return;
	}
	try {
		local ridx = reviver.GetEntityIndex();
		local sidx = subject.GetEntityIndex();
		if (ridx in GxLdBot.Reviving) {
			GxLdBot.Reviving[ridx] = sidx;
		} else {
			GxLdBot.Reviving[ridx] <- sidx;
		}
		if (sidx in GxLdBot.BeingRevived) {
			GxLdBot.BeingRevived[sidx] = ridx;
		} else {
			GxLdBot.BeingRevived[sidx] <- ridx;
		}
		GxLdBot.Log("revive begin " + GxLdBot.SafeName(reviver) +
			" -> " + GxLdBot.SafeName(subject));
	} catch (e) {
	}
}

function GxLdBot::ClearReviveState(reviver, subject) {
	GxLdBot.ClearReviveStateFor(reviver);
	GxLdBot.ClearReviveStateFor(subject);
}

function GxLdBot::ClearReviveStateFor(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return;
	}
	local idx = player.GetEntityIndex();
	if (idx in GxLdBot.Reviving) {
		local subjectIdx = GxLdBot.Reviving[idx];
		delete GxLdBot.Reviving[idx];
		if (subjectIdx in GxLdBot.BeingRevived) {
			delete GxLdBot.BeingRevived[subjectIdx];
		}
	}
	if (idx in GxLdBot.BeingRevived) {
		local reviverIdx = GxLdBot.BeingRevived[idx];
		delete GxLdBot.BeingRevived[idx];
		if (reviverIdx in GxLdBot.Reviving) {
			delete GxLdBot.Reviving[reviverIdx];
		}
	}
}

function GxLdBot::IsPlayerReviving(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return false;
	}
	try {
		return player.GetEntityIndex() in GxLdBot.Reviving;
	} catch (e) {
		return false;
	}
}

function GxLdBot::IsPlayerBeingRevived(player) {
	if (!GxLdBot.IsValidEntity(player)) {
		return false;
	}
	try {
		return player.GetEntityIndex() in GxLdBot.BeingRevived;
	} catch (e) {
		return false;
	}
}

function GxLdBot::Think() {
	if (GxLdBot.UpdateSleepState()) {
		return 1.0;
	}

	GxLdBot.EnsureProfiles(false);
	GxLdBot.ObserveTeamMovement();
	GxLdBot.SafeCall("dynamic_cvars", function() {
		GxLdBot.UpdateDynamicCvars();
	});

	// Run registered module think hooks; each is guarded so one failure
	// cannot stop the others or kill the think loop.
	foreach (idx, hook in GxLdBot.ThinkHooks) {
		GxLdBot.SafeCall("think:" + hook.name, hook.fn);
	}

	if (GxLdBot.Debug) {
		local now = GxLdBot.Now();
		if (now - GxLdBot.LastStatusPrint >= GxLdBot.Settings.DebugStatusInterval) {
			GxLdBot.LastStatusPrint = now;
			GxLdBot.Log("think profiles=" + GxLdBot.Profiles.len());
		}
	}

	return 1.0;
}

// Modules call this at include time to register a recurring think callback.
function GxLdBot::RegisterThink(name, fn) {
	GxLdBot.ThinkHooks.append({ name = name, fn = fn });
}

// Modules call this to register a per-round reset/setup callback.
function GxLdBot::RegisterRound(name, fn) {
	GxLdBot.RoundHooks.append({ name = name, fn = fn });
}

function GxLdBot::StartThink() {
	if (GxLdBot.ThinkEntity != null && GxLdBot.IsValidEntity(GxLdBot.ThinkEntity)) {
		return;
	}

	try {
		local ent = SpawnEntityFromTable("info_target", { targetname = "gxldbot_think" });
		if (ent == null) {
			GxLdBot.Log("failed to create think entity", true);
			return;
		}

		ent.ValidateScriptScope();
		local scope = ent.GetScriptScope();
		scope["gxldbot_think"] <- function() {
			return ::GxLdBot.Think();
		};
		AddThinkToEnt(ent, "gxldbot_think");
		GxLdBot.ThinkEntity = ent;
		GxLdBot.Log("think entity started", true);
	} catch (e) {
		GxLdBot.Log("StartThink failed: " + e, true);
	}
}

function GxLdBot::RoundStart() {
	// round_start and round_start_post_nav can both fire; only init once per round.
	local now = GxLdBot.Now();
	if (now - GxLdBot.LastRoundInit < 1.0) {
		return;
	}
	GxLdBot.LastRoundInit = now;

	GxLdBot.Profiles = {};
	GxLdBot.Cards = {};
	GxLdBot.Focus = {};
	GxLdBot.Composure = {};
	GxLdBot.Claims = {};
	GxLdBot.LastSpeak = {};
	GxLdBot.LastScout = {};
	GxLdBot.LastScoutTarget = {};
	GxLdBot.LastAttack = {};
	GxLdBot.Reviving = {};
	GxLdBot.BeingRevived = {};
	if ("HealIntent" in GxLdBot) {
		GxLdBot.HealIntent = {};
	}
	GxLdBot.LastTeamOrigin = null;
	GxLdBot.RoundStartOrigin = null;
	GxLdBot.LastTeamMoveTime = now;
	GxLdBot.LastStallNotice = 0.0;
	if (GxLdBot.UpdateSleepState()) {
		GxLdBot.StartThink();
		return;
	}
	GxLdBot.ApplyMildCvars();
	GxLdBot.EnsureProfiles(true);

	// Run registered module round hooks (role assignment, etc.).
	foreach (idx, hook in GxLdBot.RoundHooks) {
		GxLdBot.SafeCall("round:" + hook.name, hook.fn);
	}

	GxLdBot.StartThink();
	GxLdBot.Notify("round_start", "v" + GxLdBot.Version +
		" active cards=" + GxLdBot.Settings.EnableCards +
		" rescue=" + GxLdBot.Settings.EnableRescue, 8.0);
	GxLdBot.Log("round start initialized", true);
}

function GxLdBot::Init() {
	if (GxLdBot.Initialized) {
		return;
	}

	GxLdBot.Initialized = true;
	GxLdBot.ApplyMode(GxLdBot.Settings.Mode, false, null);
	GxLdBot.StartThink();
	GxLdBot.UpdateSleepState();
	if (!GxLdBot.Sleeping && "StartArbiterThink" in GxLdBot) {
		GxLdBot.StartArbiterThink();
	}
	GxLdBot.Log("loaded v" + GxLdBot.Version + " commands: !hbot_help", true);
}

gxldbotSetSlot(GxLdBot, "Events", {});

// Behavior modules. Each attaches methods to GxLdBot and registers think/round
// hooks and its own game-event handlers via GxLdBot.Events before collection below.
GxLdBot.SafeCall("include:cards", function() { IncludeScript("gxldbot/cards"); });
GxLdBot.SafeCall("include:squad", function() { IncludeScript("gxldbot/squad"); });
GxLdBot.SafeCall("include:survival", function() { IncludeScript("gxldbot/survival"); });
GxLdBot.SafeCall("include:social", function() { IncludeScript("gxldbot/social"); });
GxLdBot.SafeCall("include:progress", function() { IncludeScript("gxldbot/progress"); });
GxLdBot.SafeCall("include:actions", function() { IncludeScript("gxldbot/actions"); });

GxLdBot.Events.OnGameEvent_round_start <- function(event) {
	::GxLdBot.RoundStart();
}

GxLdBot.Events.OnGameEvent_round_start_post_nav <- function(event) {
	::GxLdBot.RoundStart();
}

GxLdBot.Events.OnGameEvent_player_spawn <- function(event) {
	::GxLdBot.EnsureProfiles(false);
}

GxLdBot.Events.OnGameEvent_player_team <- function(event) {
	::GxLdBot.ClearReviveStateFor(::GxLdBot.PlayerFromEvent(event, "userid"));
	::GxLdBot.EnsureProfiles(false);
}

GxLdBot.Events.OnGameEvent_player_disconnect <- function(event) {
	::GxLdBot.ClearReviveStateFor(::GxLdBot.PlayerFromEvent(event, "userid"));
	::GxLdBot.EnsureProfiles(false);
}

GxLdBot.Events.OnGameEvent_player_bot_replace <- function(event) {
	::GxLdBot.EnsureProfiles(false);
}

GxLdBot.Events.OnGameEvent_bot_player_replace <- function(event) {
	::GxLdBot.EnsureProfiles(false);
}

GxLdBot.Events.OnGameEvent_player_say <- function(event) {
	::GxLdBot.OnPlayerSay(event);
}

GxLdBot.Events.OnGameEvent_player_death <- function(event) {
	::GxLdBot.ClearReviveStateFor(::GxLdBot.PlayerFromEvent(event, "userid"));
}

GxLdBot.Events.OnGameEvent_revive_begin <- function(event) {
	::GxLdBot.SetReviveState(
		::GxLdBot.PlayerFromEvent(event, "userid"),
		::GxLdBot.PlayerFromEvent(event, "subject"));
}

GxLdBot.Events.OnGameEvent_revive_end <- function(event) {
	::GxLdBot.ClearReviveState(
		::GxLdBot.PlayerFromEvent(event, "userid"),
		::GxLdBot.PlayerFromEvent(event, "subject"));
}

GxLdBot.Events.OnGameEvent_revive_success <- function(event) {
	::GxLdBot.ClearReviveState(
		::GxLdBot.PlayerFromEvent(event, "userid"),
		::GxLdBot.PlayerFromEvent(event, "subject"));
}

try {
	__CollectEventCallbacks(GxLdBot.Events, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
} catch (e) {
	GxLdBot.Log("event registration failed: " + e, true);
}

function GxLdBot::InstallConsoleCommand() {
	local root = getroottable();

	if (!("GxLdBot_PreviousUserConsoleCommand" in root)) {
		root["GxLdBot_PreviousUserConsoleCommand"] <- ("UserConsoleCommand" in root)
			? root["UserConsoleCommand"] : null;
	}
	if (!("GxLdBot_PreviousModeUserConsoleCommand" in root)) {
		root["GxLdBot_PreviousModeUserConsoleCommand"] <- ("g_ModeScript" in root &&
			"UserConsoleCommand" in g_ModeScript) ? g_ModeScript.UserConsoleCommand : null;
	}
	if (!("GxLdBot_PreviousMapUserConsoleCommand" in root)) {
		root["GxLdBot_PreviousMapUserConsoleCommand"] <- ("g_MapScript" in root &&
			"UserConsoleCommand" in g_MapScript) ? g_MapScript.UserConsoleCommand : null;
	}

	local consoleCommand = function(playerScript, arg) {
		if ("GxLdBot" in getroottable() && ::GxLdBot.OnConsoleCommand(playerScript, arg)) {
			return;
		}
		if ("GxLdBot_PreviousUserConsoleCommand" in getroottable() &&
				::GxLdBot_PreviousUserConsoleCommand != null) {
			::GxLdBot_PreviousUserConsoleCommand(playerScript, arg);
			return;
		}
		if ("GxLdBot_PreviousModeUserConsoleCommand" in getroottable() &&
				::GxLdBot_PreviousModeUserConsoleCommand != null) {
			::GxLdBot_PreviousModeUserConsoleCommand(playerScript, arg);
			return;
		}
		if ("GxLdBot_PreviousMapUserConsoleCommand" in getroottable() &&
				::GxLdBot_PreviousMapUserConsoleCommand != null) {
			::GxLdBot_PreviousMapUserConsoleCommand(playerScript, arg);
		}
	};

	if ("UserConsoleCommand" in root) {
		root["UserConsoleCommand"] = consoleCommand;
	} else {
		root["UserConsoleCommand"] <- consoleCommand;
	}

	if ("g_ModeScript" in root) {
		if ("UserConsoleCommand" in g_ModeScript) {
			g_ModeScript.UserConsoleCommand = root["UserConsoleCommand"];
		} else {
			g_ModeScript.UserConsoleCommand <- root["UserConsoleCommand"];
		}
	}
	if ("g_MapScript" in root) {
		if ("UserConsoleCommand" in g_MapScript) {
			g_MapScript.UserConsoleCommand = root["UserConsoleCommand"];
		} else {
			g_MapScript.UserConsoleCommand <- root["UserConsoleCommand"];
		}
	}

	GxLdBot.Log("console commands installed: scripted_user_func hbot_status", true);
}

GxLdBot.SafeCall("install_console", function() {
	GxLdBot.InstallConsoleCommand();
});
GxLdBot.Init();
