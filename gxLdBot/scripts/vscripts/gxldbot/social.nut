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
	if (("CanControlBots" in GxLdBot && !GxLdBot.CanControlBots()) ||
			!GxLdBot.CanSpeak(bot)) {
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
	local profile = GxLdBot.GetProfile(speaker);
	local delay = GxLdBot.RandFloat(0.05, 0.28);
	if (profile != null) { delay += profile.reaction * 0.35; }
	GxLdBot.SpeechQueue.append({ bot = speaker, concept = concept, key = key,
		readyAt = GxLdBot.Now() + delay, expiresAt = GxLdBot.Now() + 1.8 });
}

function GxLdBot::ProcessSpeechQueue() {
	if (GxLdBot.SpeechQueue.len() <= 0) { return; }
	local now = GxLdBot.Now();
	local keep = [];
	foreach (i, item in GxLdBot.SpeechQueue) {
		if (now >= item.expiresAt || !GxLdBot.IsValidEntity(item.bot)) {
			if (GxLdBot.IsValidEntity(item.bot)) { GxLdBot.ReleaseClaim(item.key, item.bot); }
			continue;
		}
		if (now < item.readyAt) { keep.append(item); continue; }
		local noticed = true;
		if (item.concept.find("FriendDown") != null || item.concept.find("Warn") != null) {
			local frame = GxLdBot.GetSituation();
			if (frame.emergencyVictim != null) { noticed = GxLdBot.PerceivesEmergency(item.bot); }
			else if (frame.combat) { noticed = GxLdBot.BotAllowsAssist(item.bot); }
		}
		if (!noticed) { keep.append(item); continue; }
		if (!GxLdBot.Speak(item.bot, item.concept)) { GxLdBot.ReleaseClaim(item.key, item.bot); }
	}
	GxLdBot.SpeechQueue = keep;
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
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnHunter");
	});
}

GxLdBot.Events.OnGameEvent_tongue_grab <- function(event) {
	GxLdBot.SafeCall("co_smoker", function() {
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnSmoker");
	});
}

GxLdBot.Events.OnGameEvent_jockey_ride <- function(event) {
	GxLdBot.SafeCall("co_jockey", function() {
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnJockey");
	});
}

GxLdBot.Events.OnGameEvent_charger_carry_start <- function(event) {
	GxLdBot.SafeCall("co_charger", function() {
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(GxLdBot.VictimFromEvent(event, "victim"), "PlayerWarnCharger");
	});
}

GxLdBot.Events.OnGameEvent_tank_spawn <- function(event) {
	GxLdBot.SafeCall("co_tank", function() {
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(null, "PlayerWarnTank");
	});
}

GxLdBot.Events.OnGameEvent_witch_spawn <- function(event) {
	GxLdBot.SafeCall("co_witch", function() {
		GxLdBot.InvalidateWorldFrame();
		GxLdBot.Warn(null, "PlayerWarnWitch");
	});
}

GxLdBot.Events.OnGameEvent_player_incapacitated <- function(event) {
	GxLdBot.SafeCall("co_incap", function() {
		GxLdBot.InvalidateWorldFrame();
		local victim = GxLdBot.VictimFromEvent(event, "userid");
		GxLdBot.Warn(victim, "PlayerFriendDown");
	});
}

GxLdBot.Events.OnGameEvent_pounce_end <- function(event) { GxLdBot.InvalidateWorldFrame(); }
GxLdBot.Events.OnGameEvent_tongue_release <- function(event) { GxLdBot.InvalidateWorldFrame(); }
GxLdBot.Events.OnGameEvent_jockey_ride_end <- function(event) { GxLdBot.InvalidateWorldFrame(); }
GxLdBot.Events.OnGameEvent_charger_carry_end <- function(event) { GxLdBot.InvalidateWorldFrame(); }
GxLdBot.Events.OnGameEvent_charger_pummel_end <- function(event) { GxLdBot.InvalidateWorldFrame(); }

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
	if (("BotAllowsExpression" in GxLdBot) && !GxLdBot.BotAllowsExpression(bot)) {
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

// ---- Player directives (native concept probe + explicit debug fallback) ----

function GxLdBot::SetPlayerDirective(kind, source = "debug", player = null) {
	local now = GxLdBot.Now();
	GxLdBot.PlayerDirective = { kind = kind,
		until = now + GxLdBot.Settings.PlayerDirectiveSeconds, source = source };
	if (player != null) { GxLdBot.Chat(player, "directive=" + kind + " source=" + source); }
	GxLdBot.Log("player_directive " + kind + " source=" + source, true);
}

function GxLdBot::CaptureConcept(speaker, concept) {
	if (concept == null) { return false; }
	local text = concept.tostring().tolower();
	GxLdBot.ConceptProbe.captures++;
	GxLdBot.ConceptProbe.last = text;
	if (text.find("wait") != null) {
		GxLdBot.SetPlayerDirective("wait", "concept", null);
		return true;
	}
	if (text.find("moveon") != null || text.find("leadon") != null ||
			text.find("hurry") != null) {
		GxLdBot.SetPlayerDirective("moveon", "concept", null);
		return true;
	}
	if (text.find("look") != null) {
		GxLdBot.SetPlayerDirective("look", "concept", null);
		return true;
	}
	return false;
}

// ResponseRules/VSLib must call this endpoint; merely exposing it does not claim
// that concept capture is available. !hbot_conceptprobe reports capture count.
function GxLdBot::InstallConceptProbe() {
	if (!GxLdBot.Settings.EnableNativeDirectiveProbe) { return; }
	local root = getroottable();
	local endpoint = function(speaker, concept) {
		return ::GxLdBot.CaptureConcept(speaker, concept);
	};
	if ("GxLdBot_OnConcept" in root) { root["GxLdBot_OnConcept"] = endpoint; }
	else { root["GxLdBot_OnConcept"] <- endpoint; }
	GxLdBot.ConceptProbe.installed = true;
}

// ---- Expression scheduler --------------------------------------------------

function GxLdBot::FindAttentionPOI(bot) {
	if (!GxLdBot.IsValidEntity(bot)) { return null; }
	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return null; }
	local best = null;
	local bestScore = -999999.0;
	local classes = ["weapon_spawn", "weapon_first_aid_kit_spawn",
		"weapon_ammo_spawn", "upgrade_laser_sight", "prop_door_rotating_checkpoint",
		"prop_door_rotating"];
	foreach (i, cls in classes) {
		local ent = null;
		try {
			while (ent = Entities.FindByClassnameWithin(ent, cls, origin,
					GxLdBot.Settings.ExpressionAttentionRadius)) {
				local d = (ent.GetOrigin() - origin).Length();
				local score = 1000.0 - d + GxLdBot.RandFloat(0.0, 120.0);
				if (score > bestScore) { bestScore = score; best = ent.GetOrigin(); }
			}
		} catch (ef) {}
	}
	if (best != null) { return best; }
	local area = null;
	try { area = bot.GetLastKnownArea(); } catch (ea) {}
	if (area == null || !("CollectAdjacent" in GxLdBot)) { return null; }
	local adjacent = {};
	GxLdBot.CollectAdjacent(area, adjacent);
	foreach (id, a in adjacent) {
		try {
			if (a.IsBlocked(2, false) || a.IsBlocked(2, true) || a.IsDamaging()) { continue; }
			local pos = a.GetCenter();
			local d = (pos - origin).Length();
			if (d <= GxLdBot.Settings.ExpressionAttentionRadius) {
				local score = d + GxLdBot.RandFloat(0.0, 80.0);
				if (score > bestScore) { bestScore = score; best = pos; }
			}
		} catch (enav) {}
	}
	return best;
}

function GxLdBot::UpdateExpressionPlan(force = false) {
	local now = GxLdBot.Now();
	if (!GxLdBot.Settings.EnableExpressions ||
			(!force && (now - GxLdBot.ExpressionPlanTime) < GxLdBot.Settings.ExpressionPlanInterval)) {
		return;
	}
	GxLdBot.ExpressionPlanTime = now;
	local dead = [];
	foreach (idx, plan in GxLdBot.ExpressionPlan) {
		if (now >= plan.until) { dead.append(idx); }
	}
	foreach (i, idx in dead) { delete GxLdBot.ExpressionPlan[idx]; }
	if (GxLdBot.ExpressionPlan.len() > 0 || now < GxLdBot.ExpressionTeam.nextAt ||
			(now - GxLdBot.LastTeamMoveTime) < GxLdBot.Settings.ExpressionMinStall) { return; }

	local candidates = [];
	GxLdBot.ForEachSurvivorBot(function(bot) {
		if (!GxLdBot.IsAlive(bot) || GxLdBot.IsUncommandable(bot) ||
				!GxLdBot.BotAllowsExpression(bot)) { return; }
		local mind = GxLdBot.GetBotMind(bot);
		local profile = GxLdBot.GetProfile(bot);
		local human = GxLdBot.NearestHuman(bot);
		if (mind == null || profile == null || human == null ||
				mind.socialEnergy < GxLdBot.Settings.ExpressionEnergyCost ||
				GxLdBot.DistanceBetween(bot, human) > GxLdBot.Settings.SupportLinkDistance) { return; }
		local score = mind.socialEnergy + profile.interactionBias * 0.7 +
			profile.itemCuriosity * 0.25 + GxLdBot.RandFloat(0.0, 12.0);
		candidates.append({ bot = bot, idx = bot.GetEntityIndex(), human = human,
			mind = mind, profile = profile, score = score });
	});
	if (candidates.len() <= 0) { return; }
	candidates.sort(function(a, b) { return (a.score > b.score) ? -1 : ((a.score < b.score) ? 1 : 0); });
	local first = candidates[0];
	local directiveLook = GxLdBot.PlayerDirective.kind == "look" && now < GxLdBot.PlayerDirective.until;
	local poi = GxLdBot.FindAttentionPOI(first.bot);
	local firstKind = (directiveLook || poi == null ||
			first.profile.interactionBias >= first.profile.itemCuriosity) ? "checkin" : "attention";
	local duration = (firstKind == "attention") ? GxLdBot.Settings.ExpressionAttentionDuration
		: GxLdBot.Settings.ExpressionCheckinDuration;
	GxLdBot.ExpressionPlan[first.idx] <- { kind = firstKind, startAt = now,
		until = now + duration, human = first.human, pos = poi, initiator = true };
	first.mind.socialEnergy -= GxLdBot.Settings.ExpressionEnergyCost;
	GxLdBot.ExpressionTeam.initiatorIdx = first.idx;
	GxLdBot.ExpressionTeam.joinerIdx = -1;
	GxLdBot.ExpressionTeam.nextAt = now + GxLdBot.Settings.ExpressionTeamCooldown;

	if (GxLdBot.Settings.EnableGoof && candidates.len() > 1 &&
			GxLdBot.RandInt(1, 100) <= GxLdBot.Settings.ExpressionJoinChance) {
		local join = candidates[1];
		local delay = GxLdBot.RandFloat(GxLdBot.Settings.ExpressionJoinDelayMin,
			GxLdBot.Settings.ExpressionJoinDelayMax);
		GxLdBot.ExpressionPlan[join.idx] <- { kind = "goof", startAt = now + delay,
			until = now + delay + GxLdBot.Settings.GoofDuration, human = join.human,
			pos = null, initiator = false };
		join.mind.socialEnergy -= GxLdBot.Settings.ExpressionEnergyCost;
		GxLdBot.ExpressionTeam.joinerIdx = join.idx;
	}
}

function GxLdBot::ExpressionIntentFor(bot) {
	GxLdBot.UpdateExpressionPlan(false);
	if (!GxLdBot.IsValidEntity(bot)) { return null; }
	local idx = bot.GetEntityIndex();
	if (!(idx in GxLdBot.ExpressionPlan)) { return null; }
	local plan = GxLdBot.ExpressionPlan[idx];
	local now = GxLdBot.Now();
	if (now < plan.startAt || now >= plan.until || !GxLdBot.BotAllowsExpression(bot)) { return null; }
	return { kind = "expression", expressionKind = plan.kind, human = plan.human,
		pos = plan.pos, until = plan.until };
}

function GxLdBot::PrintMinds(player) {
	GxLdBot.GetSituation();
	GxLdBot.Chat(player, "team phase=" + GxLdBot.TeamModel.phase +
		" for=" + (GxLdBot.Now() - GxLdBot.TeamModel.since) + "s" +
		" threatRecords=" + GxLdBot.ThreatSampler.records.len() +
		" assistOwner=" + GxLdBot.TeamAssistPlan.owner);
	GxLdBot.ForEachSurvivorBot(function(bot) {
		local mind = GxLdBot.GetBotMind(bot);
		GxLdBot.Chat(player, GxLdBot.SafeName(bot) + " sees=" + mind.perceivedPhase +
			" stress=" + mind.stress.tointeger() + " momentum=" + mind.momentum.tointeger() +
			" social=" + mind.socialEnergy.tointeger());
	});
}

// ---- Registration ----------------------------------------------------------
// Idle is no longer its own think hook — the action arbiter (actions.nut) calls
// IdleIntentFor / IdleSpeak as its lowest-priority behavior. Callout event
// handlers above stay event-driven and are unaffected.

GxLdBot.RegisterThink("speech_queue", function() {
	GxLdBot.ProcessSpeechQueue();
});
