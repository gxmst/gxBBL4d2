// gxLdBot social module: callouts (#1), idle interaction (#7).
//
// This is the most fully ENACTED module: making a survivor speak via
// SpeakResponseConcept is verified working (responserules.nut uses it). Bots
// warn on real game events (pin, special spawn) and announce heals, which is
// the single highest-impact "feels like a teammate" signal. Idle behavior makes
// a stalled bot turn toward / drift toward a lagging human instead of standing
// silent, without forcing "wait here" style voice lines.

// Pick the survivor bot that should voice a warning: closest alive bot to the
// reference entity (it most plausibly "noticed"). Can optionally skip bots
// still inside their personal speech cooldown or skip the victim.
function GxLdBot::PickSpeaker(refEnt, requireReady = false, excludeEnt = null) {
	local best = null;
	local bestDist = 999999.0;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		if (!GxLdBot.IsAlive(bot)) {
			return;
		}
		if (excludeEnt != null && bot == excludeEnt) {
			return;
		}
		if (requireReady && !GxLdBot.CanSpeak(bot)) {
			return;
		}
		local d = (refEnt != null && GxLdBot.IsValidEntity(refEnt))
			? GxLdBot.DistanceBetween(bot, refEnt) : 0.0;
		if (d < bestDist) {
			bestDist = d;
			best = bot;
		}
	});
	return best;
}

function GxLdBot::CanSpeak(bot) {
	if (!GxLdBot.Settings.EnableCallouts || !GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	local idx = bot.GetEntityIndex();
	local now = GxLdBot.Now();
	return !(idx in GxLdBot.LastSpeak &&
		(now - GxLdBot.LastSpeak[idx]) < GxLdBot.Settings.CalloutCooldown);
}

function GxLdBot::MarkSpoken(bot) {
	GxLdBot.SetTableSlot(GxLdBot.LastSpeak, bot.GetEntityIndex(), GxLdBot.Now());
}

// Make a specific bot speak a response concept, rate-limited per bot.
function GxLdBot::Speak(bot, concept) {
	if (!GxLdBot.CanSpeak(bot)) {
		return false;
	}

	// Primary path: EntFireByHandle targets the bot directly.
	if ("EntFireByHandle" in getroottable()) {
		try {
			EntFireByHandle(bot, "SpeakResponseConcept", concept, 0.0, null, null);
			GxLdBot.MarkSpoken(bot);
			GxLdBot.Log("callout " + GxLdBot.SafeName(bot) + " concept=" + concept);
			return true;
		} catch (e) {
			GxLdBot.Log("Speak EntFireByHandle failed, trying DoEntFire: " + e, true);
		}
	}

	// Fallback: the older DoEntFire("!self", ..., activator) form VSLib uses.
	try {
		DoEntFire("!self", "SpeakResponseConcept", concept, 0.0, null, bot);
		GxLdBot.MarkSpoken(bot);
		GxLdBot.Log("callout(fallback) " + GxLdBot.SafeName(bot) + " concept=" + concept);
		return true;
	} catch (e2) {
		GxLdBot.Log("Speak DoEntFire failed: " + e2, true);
		return false;
	}
}

// Convenience: warn about a threat near `nearEnt` using `concept`. Uses the
// claim table so only one bot calls out a given threat — no overlapping
// "Hunter!" from three bots at once.
function GxLdBot::Warn(nearEnt, concept) {
	local speaker = GxLdBot.PickSpeaker(nearEnt, true, nearEnt);
	if (speaker == null) {
		return;
	}
	// Key the claim on the victim if we have one, else the concept itself.
	local key = "warn:" + ((nearEnt != null && GxLdBot.IsValidEntity(nearEnt))
		? nearEnt.GetEntityIndex().tostring() : concept);
	if (!GxLdBot.TryClaim(key, speaker)) {
		return;
	}
	if (!GxLdBot.Speak(speaker, concept)) {
		GxLdBot.ReleaseClaim(key, speaker);
	}
}

// Called by survival.nut when a bot decides to heal.
function GxLdBot::OnHealIntent(bot) {
	GxLdBot.Speak(bot, "PlayerHealing");
}

// ---- Callout event handlers ------------------------------------------------
//
// Map real L4D2 game events to survivor warning concepts. Speaker is the bot
// nearest the victim. Speak() rate-limits, so overlapping specials won't spam.

function GxLdBot::VictimFromEvent(event, field) {
	if (!(field in event)) {
		return null;
	}
	try {
		return GetPlayerFromUserID(event[field]);
	} catch (e) {
		return null;
	}
}

GxLdBot.Events.OnGameEvent_lunge_pounce <- function(event) {
	GxLdBot.SafeCall("co_pounce", function() {
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnHunter");
	});
}

GxLdBot.Events.OnGameEvent_tongue_grab <- function(event) {
	GxLdBot.SafeCall("co_smoker", function() {
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnSmoker");
	});
}

GxLdBot.Events.OnGameEvent_jockey_ride <- function(event) {
	GxLdBot.SafeCall("co_jockey", function() {
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnJockey");
	});
}

GxLdBot.Events.OnGameEvent_charger_carry_start <- function(event) {
	GxLdBot.SafeCall("co_charger", function() {
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnCharger");
	});
}

GxLdBot.Events.OnGameEvent_tank_spawn <- function(event) {
	GxLdBot.SafeCall("co_tank", function() {
		GxLdBot.Warn(null, "PlayerWarnTank");
	});
}

GxLdBot.Events.OnGameEvent_witch_spawn <- function(event) {
	GxLdBot.SafeCall("co_witch", function() {
		GxLdBot.Warn(null, "PlayerWarnWitch");
	});
}

GxLdBot.Events.OnGameEvent_player_incapacitated <- function(event) {
	GxLdBot.SafeCall("co_incap", function() {
		local victim = GxLdBot.VictimFromEvent(event, "userid");
		// A bystander bot calls it out, not the downed player.
		local speaker = GxLdBot.PickSpeaker(victim, true, victim);
		if (speaker != null) {
			GxLdBot.Speak(speaker, "PlayerFriendDown");
		}
	});
}

// ---- Idle interaction (#7) -------------------------------------------------
//
// When the team is stalled in a safe state, impatient bots stop being statues.
// Decision only: returns the human a bot should drift toward / face during a
// calm stall, or null. The action arbiter (actions.nut) enacts the move + face
// and calls IdleSpeak for debug logging. Point/flanker bots idle first; other
// bots need a very low waitBias.

function GxLdBot::IdleIntentFor(bot) {
	if (!GxLdBot.Settings.EnableIdle) {
		return null;
	}
	local now = GxLdBot.Now();
	local stalledFor = now - GxLdBot.LastTeamMoveTime;
	if (stalledFor < GxLdBot.Settings.StallSeconds) {
		return null;
	}
	// Idle behavior is for calm stalls only; never under threat.
	if (GxLdBot.TeamUnderStress()) {
		return null;
	}

	local profile = GxLdBot.GetProfile(bot);
	if (profile == null) {
		return null;
	}
	local isScout = ("IsScoutRole" in GxLdBot) && GxLdBot.IsScoutRole(profile);
	local waitGate = ("IdleWaitBiasGate" in GxLdBot.Settings) ? GxLdBot.Settings.IdleWaitBiasGate : 12;
	local scoutAlways = !("IdleScoutAlways" in GxLdBot.Settings) || GxLdBot.Settings.IdleScoutAlways;
	if ((!scoutAlways || !isScout) && profile.waitBias > waitGate) {
		return null;
	}

	// May be null (all-bot game) — the arbiter treats a null human as "no idle".
	return GxLdBot.NearestHuman(bot);
}

// Vocalize the stall, rate-limited per bot (called by the arbiter when it drives
// an idle approach). Kept here so idle personality logging lives with social
// behavior, without forcing "wait here" style voice lines.
function GxLdBot::IdleSpeak(bot, human) {
	local profile = GxLdBot.GetProfile(bot);
	local targetName = (human != null) ? GxLdBot.SafeName(human) : "team";
	if (profile != null) {
		GxLdBot.Log("idle " + profile.name + " face=" + targetName +
			" waitBias=" + profile.waitBias);
	}
}

// ---- Registration ----------------------------------------------------------
// Idle is no longer its own think hook — the action arbiter (actions.nut) calls
// IdleIntentFor / IdleSpeak as its lowest-priority behavior. Callout event
// handlers above stay event-driven and are unaffected.
