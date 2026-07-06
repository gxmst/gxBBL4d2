// gxLdBot actions module: the single Action Arbiter (0.3 real-behavior layer).
//
// This module is the ONE place allowed to issue CommandABot / forced buttons to
// a survivor bot. Every tick (its own ~0.18s think entity) it picks the single
// highest-priority intent per bot and enacts it; when no intent applies it hands
// the bot back to the vanilla engine with BOT_CMD_RESET. General combat mostly
// stays vanilla; 0.4 adds only a narrow close-horde assist attack burst.
//
// Priority (high -> low):
//   rescue > defend > retreat > cover > heal > shove > escort > assist >
//   progress > scout > idle > (none -> reset to vanilla)
//   Rescue is off by default in 0.6 so vanilla rescue remains the normal path.
//
// Enactment primitives are all verified against the shipped Advanced Bot AI mod:
//   CommandABot cmd 0/1/2/3, m_afButtonForced shove, SnapEyeAngles aim,
//   m_iShovePenalty / m_flNextSecondaryAttack shove reset, pin NetProps.

if (!("ShoveCooldownUntil" in GxLdBot)) {
	GxLdBot.ShoveCooldownUntil <- {};
}

// ---- low-level enact primitives --------------------------------------------

function GxLdBot::BotAttackTarget(bot, target) {
	if (!("CommandABot" in getroottable()) ||
			!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(target)) {
		return;
	}
	try {
		CommandABot({ cmd = 0, target = target, bot = bot });
	} catch (e) {
		GxLdBot.Log("BotAttackTarget failed: " + e, true);
	}
}

function GxLdBot::BotMoveTo(bot, pos) {
	if (!("CommandABot" in getroottable()) || !GxLdBot.IsValidEntity(bot) || pos == null) {
		return;
	}
	try {
		CommandABot({ cmd = 1, pos = pos, bot = bot });
	} catch (e) {
		GxLdBot.Log("BotMoveTo failed: " + e, true);
	}
}

function GxLdBot::BotRetreatFrom(bot, threat) {
	if (!("CommandABot" in getroottable()) ||
			!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(threat)) {
		return;
	}
	try {
		CommandABot({ cmd = 2, target = threat, bot = bot });
	} catch (e) {
		GxLdBot.Log("BotRetreatFrom failed: " + e, true);
	}
}

// Hand a bot back to the engine's own AI: BOT_CMD_RESET (3) cancels any move /
// attack order we issued. The arbiter calls this whenever it drops an action so
// a bot is never left executing a stale command.
function GxLdBot::BotResetCommand(bot) {
	if (!("CommandABot" in getroottable()) || !GxLdBot.IsValidEntity(bot)) {
		return;
	}
	try {
		CommandABot({ cmd = 3, bot = bot });
		GxLdBot.Log("reset " + GxLdBot.SafeName(bot));
	} catch (e) {
		GxLdBot.Log("BotResetCommand failed: " + e, true);
	}
}

// Snap a bot's aim toward a target. Used only as a single nudge right before a
// shove / during idle facing — never a continuous per-frame aim takeover (that
// is the "superhuman aim" the design avoids). Mirrors the reference's QAngle
// math (ai_utils.nut CreateQAngle).
function GxLdBot::FaceEntity(bot, target) {
	if (!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(target)) {
		return;
	}
	try {
		local d = target.GetOrigin() - bot.EyePosition();
		local yaw = atan2(d.y, d.x) * 180.0 / PI;
		local flat = sqrt(d.x * d.x + d.y * d.y);
		local pitch = atan2(-d.z, flat) * 180.0 / PI;
		bot.SnapEyeAngles(QAngle(pitch, yaw, 0));
	} catch (e) {
		GxLdBot.Log("FaceEntity failed: " + e, true);
	}
}

// Hold the shove button so the bot shoves a special off a pinned teammate. We
// zero the shove penalty + secondary-attack timer each tick so repeated shoves
// land (matching ai-shoveinfected.nut), and face the target first. The bit is
// cleared by ClearShove whenever the bot is not shoving, so it never sticks.
function GxLdBot::SetShove(bot, target) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return;
	}
	try { NetProps.SetPropInt(bot, "m_iShovePenalty", 0); } catch (e) {}
	try {
		local wep = bot.GetActiveWeapon();
		if (GxLdBot.IsValidEntity(wep)) {
			NetProps.SetPropFloat(wep, "m_flNextSecondaryAttack", GxLdBot.Now() - 1.0);
		}
	} catch (e2) {}

	if (GxLdBot.IsValidEntity(target)) {
		GxLdBot.FaceEntity(bot, target);
	}

	try {
		local b = NetProps.GetPropInt(bot, "m_afButtonForced");
		if ((b & GxLdBot.BTN_SHOVE) == 0) {
			NetProps.SetPropInt(bot, "m_afButtonForced", b | GxLdBot.BTN_SHOVE);
			GxLdBot.Log("shove " + GxLdBot.SafeName(bot));
		}
	} catch (e3) {
		GxLdBot.Log("SetShove failed: " + e3, true);
	}
}

function GxLdBot::ClearShove(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return;
	}
	try {
		local b = NetProps.GetPropInt(bot, "m_afButtonForced");
		if ((b & GxLdBot.BTN_SHOVE) != 0) {
			NetProps.SetPropInt(bot, "m_afButtonForced", b & ~GxLdBot.BTN_SHOVE);
		}
	} catch (e) {}
}

// ---- detection helpers ------------------------------------------------------

// Find the entity index of a survivor (small loop; avoids EntIndexToHScript).
function GxLdBot::SurvivorByIndex(idx) {
	local found = null;
	GxLdBot.ForEachSurvivor(function(s) {
		if (found != null) {
			return;
		}
		try {
			if (s.GetEntityIndex() == idx) {
				found = s;
			}
		} catch (e) {}
	});
	return found;
}

// If `victim` is pinned by a special, return { special, shovable }, else null.
// shovable = the pin can be broken by an adjacent shove (hunter/jockey/charger
// pummel); smoker tongue and charger carry are shoot-only.
function GxLdBot::PinnedSpecialOf(victim) {
	if (!GxLdBot.IsValidEntity(victim)) {
		return null;
	}
	local props = [
		{ p = "m_pounceAttacker", shove = true },  // hunter
		{ p = "m_jockeyAttacker", shove = true },  // jockey
		{ p = "m_pummelAttacker", shove = true },  // charger pummel
		{ p = "m_tongueOwner",   shove = false },  // smoker (shoot)
		{ p = "m_carryAttacker", shove = false }   // charger carry (shoot)
	];
	local result = null;
	foreach (i, e in props) {
		if (result != null) {
			continue;
		}
		try {
			if (NetProps.GetPropInt(victim, e.p) > 0) {
				local sp = NetProps.GetPropEntity(victim, e.p);
				if (GxLdBot.IsValidEntity(sp) && GxLdBot.IsAlive(sp)) {
					result = { special = sp, shovable = e.shove };
				}
			}
		} catch (ex) {}
	}
	return result;
}

// True if this bot should heal right now: has heal intent AND combat is light enough.
function GxLdBot::HealIntentFor(bot) {
	if (!GxLdBot.Settings.EnableHeal) {
		return false;
	}
	local idx = bot.GetEntityIndex();
	if (!("HealIntent" in GxLdBot) || !(idx in GxLdBot.HealIntent) || !GxLdBot.HealIntent[idx]) {
		return false;
	}
	local human = GxLdBot.NearestHuman(bot);
	if (human != null && GxLdBot.DistanceBetween(bot, human) > GxLdBot.Settings.EscortCatchupDistance) {
		return false;
	}
	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return false; }
	local commons = 0;
	try {
		local ent = null;
		while (ent = Entities.FindByClassnameWithin(ent, "infected", origin, GxLdBot.Settings.HealCombatRadius)) {
			commons++;
			if (commons >= GxLdBot.Settings.HealCommonCount) {
				return false;
			}
		}
	} catch (e2) {}
	try {
		local p = null;
		while (p = Entities.FindByClassnameWithin(p, "player", origin, GxLdBot.Settings.HealCombatRadius)) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				return false;
			}
		}
	} catch (e3) {}
	return true;
}

function GxLdBot::HealShouldContinue(bot, idx, now) {
	if (!GxLdBot.Settings.EnableHeal || !GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	if (!(idx in GxLdBot.Action) || GxLdBot.Action[idx].kind != "heal") {
		return false;
	}
	local a = GxLdBot.Action[idx];
	if (now >= a.until) {
		return false;
	}
	if (!("HasMedkit" in GxLdBot) || !GxLdBot.HasMedkit(bot)) {
		return false;
	}
	return true;
}

function GxLdBot::ClearHeal(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return;
	}
	try {
		local b = NetProps.GetPropInt(bot, "m_afButtonForced");
		if ((b & GxLdBot.BTN_USE) != 0) {
			NetProps.SetPropInt(bot, "m_afButtonForced", b & ~GxLdBot.BTN_USE);
		}
	} catch (e) {}
}

function GxLdBot::CountCommonsAround(origin, radius) {
	local count = 0;
	try {
		local ent = null;
		while (ent = Entities.FindByClassnameWithin(ent, "infected", origin, radius)) {
			count++;
		}
	} catch (e) {}
	return count;
}

function GxLdBot::NearestCommonAround(origin, radius) {
	local best = null;
	local bestDist = 999999.0;
	try {
		local ent = null;
		while (ent = Entities.FindByClassnameWithin(ent, "infected", origin, radius)) {
			local d = (ent.GetOrigin() - origin).Length();
			if (d < bestDist) {
				best = ent;
				bestDist = d;
			}
		}
	} catch (e) {}
	return best;
}

function GxLdBot::CombatShoveTargetFor(bot, idx, now) {
	if (!GxLdBot.Settings.EnableShove || !GxLdBot.IsValidEntity(bot)) {
		return null;
	}

	if (idx in GxLdBot.Action && GxLdBot.Action[idx].kind == "shove") {
		local active = GxLdBot.Action[idx];
		if (now < active.until && "target" in active && GxLdBot.IsValidEntity(active.target)) {
			return active.target;
		}
	}

	if (idx in GxLdBot.ShoveCooldownUntil && now < GxLdBot.ShoveCooldownUntil[idx]) {
		return null;
	}

	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return null; }

	try {
		local p = null;
		local best = null;
		local bestDist = 999999.0;
		while (p = Entities.FindByClassnameWithin(p, "player", origin,
				GxLdBot.Settings.CombatShoveSpecialRadius)) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				local d = (p.GetOrigin() - origin).Length();
				if (d < bestDist) {
					best = p;
					bestDist = d;
				}
			}
		}
		if (best != null) {
			return best;
		}
	} catch (e2) {}

	return GxLdBot.NearestCommonAround(origin, GxLdBot.Settings.CombatShoveRadius);
}

function GxLdBot::ReviverFor(victim) {
	if (!GxLdBot.IsValidEntity(victim)) {
		return null;
	}
	local sidx = victim.GetEntityIndex();
	if (!(sidx in GxLdBot.BeingRevived)) {
		return null;
	}
	return GxLdBot.SurvivorByIndex(GxLdBot.BeingRevived[sidx]);
}

// A bot we must never command: pinned/incapped/hanging/staggering, or busy
// reviving a downed teammate. Fail-safe: any positive check wins.
function GxLdBot::IsUncommandable(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return true;
	}
	try { if (bot.IsDominatedBySpecialInfected()) return true; } catch (e) {}
	try { if (bot.IsIncapacitated()) return true; } catch (e1) {}
	try { if (bot.IsHangingFromLedge()) return true; } catch (e2) {}
	try { if (bot.IsStaggering()) return true; } catch (e3) {}
	if (GxLdBot.IsPlayerReviving(bot)) {
		return true;
	}
	return false;
}

// Does this bot already own a fresh rescue/cover claim other than exceptKey?
function GxLdBot::OwnsHighPriorityClaim(bot, exceptKey) {
	local idx = bot.GetEntityIndex();
	local now = GxLdBot.Now();
	local owns = false;
	foreach (key, c in GxLdBot.Claims) {
		if (owns || key == exceptKey || c.owner != idx) {
			continue;
		}
		if ((now - c.time) >= GxLdBot.Settings.ClaimExpiry) {
			continue;
		}
		if ((key.len() >= 7 && key.slice(0, 7) == "rescue:") ||
				(key.len() >= 6 && key.slice(0, 6) == "cover:")) {
			owns = true;
		}
	}
	return owns;
}

// ---- rescue assignment ------------------------------------------------------

// Per-bot reaction delay before a committed rescuer actually moves: random base
// * composure (rattled = slower) * personality (high rescueBias = faster). This
// is what makes rescues read as human instead of all-bots-snap-at-once.
function GxLdBot::ComputeRescueDelay(bot) {
	local delayBase = GxLdBot.RandFloat(GxLdBot.Settings.RescueDelayMin, GxLdBot.Settings.RescueDelayMax);
	local scale = 1.0;
	try { scale = GxLdBot.ReactionScale(bot); } catch (e) {}
	local profile = GxLdBot.GetProfile(bot);
	local biasFactor = 1.0;
	if (profile != null) {
		biasFactor = 1.0 - ((profile.rescueBias - 90) / 100.0); // ~0.9 .. 1.1
	}
	local d = delayBase * scale * biasFactor;
	return (d < 0.05) ? 0.05 : d;
}

// Pre-pass: ensure each pinned victim has exactly one claimed rescuer. Only the
// nearest eligible bot (weighted by rescueBias) is claimed; an existing fresh
// claim is left alone so the rescuer is stable across ticks.
function GxLdBot::AssignRescues(now) {
	if (!GxLdBot.Settings.EnableRescue) {
		return;
	}
	GxLdBot.ForEachSurvivor(function(victim) {
		if (!GxLdBot.IsAlive(victim)) {
			return;
		}
		if (GxLdBot.PinnedSpecialOf(victim) == null) {
			return;
		}
		local key = "rescue:" + victim.GetEntityIndex();
		if (key in GxLdBot.Claims) {
			local c = GxLdBot.Claims[key];
			if ((now - c.time) < GxLdBot.Settings.ClaimExpiry) {
				return; // someone is already on it
			}
		}
		local best = null;
		local bestScore = 999999.0;
		GxLdBot.ForEachSurvivorBot(function(b) {
			if (b == victim || !GxLdBot.IsAlive(b) || GxLdBot.IsUncommandable(b)) {
				return;
			}
			if (GxLdBot.OwnsHighPriorityClaim(b, key)) {
				return;
			}
			local profile = GxLdBot.GetProfile(b);
			local bias = (profile != null) ? profile.rescueBias : 80;
			local score = GxLdBot.DistanceBetween(b, victim) - bias * 2.0;
			if (score < bestScore) {
				bestScore = score;
				best = b;
			}
		});
		if (best != null) {
			GxLdBot.TryClaim(key, best);
		}
	});
}

// Pre-pass: assign one spare guard to a downed teammate, but only once a helper
// is already adjacent (a revive in progress) so we never pull the reviver away.
function GxLdBot::AssignCover(now) {
	if (!GxLdBot.Settings.EnableCover) {
		return;
	}
	GxLdBot.ForEachSurvivor(function(victim) {
		if (!GxLdBot.IsAlive(victim)) {
			return;
		}
		local down = false;
		try { down = victim.IsIncapacitated() || victim.IsHangingFromLedge(); } catch (e) { return; }
		if (!down) {
			return;
		}
		try { if (victim.IsDominatedBySpecialInfected()) return; } catch (e2) {}
		local reviver = GxLdBot.ReviverFor(victim);
		if (reviver == null) {
			return; // nobody reviving yet — let a bot go do it (vanilla)
		}

		local key = "cover:" + victim.GetEntityIndex();
		if (key in GxLdBot.Claims) {
			local c = GxLdBot.Claims[key];
			if ((now - c.time) < GxLdBot.Settings.ClaimExpiry) {
				return;
			}
		}
		local best = null;
		local bestD = 999999.0;
		GxLdBot.ForEachSurvivorBot(function(b) {
			if (b == victim || b == reviver || !GxLdBot.IsAlive(b) ||
					GxLdBot.IsUncommandable(b)) {
				return;
			}
			if (GxLdBot.OwnsHighPriorityClaim(b, key)) {
				return;
			}
			local d = GxLdBot.DistanceBetween(b, victim);
			if (d < bestD) {
				bestD = d;
				best = b;
			}
		});
		if (best != null) {
			GxLdBot.TryClaim(key, best);
		}
	});
}

// Return { victim, special, shovable } if this bot owns a fresh rescue claim for
// a still-pinned victim, else null (releasing stale claims as it goes).
function GxLdBot::RescueVictimFor(bot) {
	local idx = bot.GetEntityIndex();
	local now = GxLdBot.Now();
	local result = null;
	local release = [];
	foreach (key, c in GxLdBot.Claims) {
		if (c.owner != idx) {
			continue;
		}
		if (key.len() < 7 || key.slice(0, 7) != "rescue:") {
			continue;
		}
		if ((now - c.time) >= GxLdBot.Settings.ClaimExpiry) {
			release.append(key);
			continue;
		}
		if (result != null) {
			continue;
		}
		local victim = GxLdBot.SurvivorByIndex(key.slice(7).tointeger());
		if (victim == null || !GxLdBot.IsAlive(victim)) {
			release.append(key);
			continue;
		}
		local pin = GxLdBot.PinnedSpecialOf(victim);
		if (pin == null) {
			release.append(key);
			continue;
		}
		result = { victim = victim, special = pin.special, shovable = pin.shovable };
	}
	foreach (i, k in release) {
		if (k in GxLdBot.Claims && GxLdBot.Claims[k].owner == idx) {
			delete GxLdBot.Claims[k];
		}
	}
	return result;
}

// Return the downed victim this bot owns a fresh cover claim for, else null.
function GxLdBot::CoverVictimFor(bot) {
	local idx = bot.GetEntityIndex();
	local now = GxLdBot.Now();
	local result = null;
	local release = [];
	foreach (key, c in GxLdBot.Claims) {
		if (c.owner != idx) {
			continue;
		}
		if (key.len() < 6 || key.slice(0, 6) != "cover:") {
			continue;
		}
		if ((now - c.time) >= GxLdBot.Settings.ClaimExpiry) {
			release.append(key);
			continue;
		}
		if (result != null) {
			continue;
		}
		local victim = GxLdBot.SurvivorByIndex(key.slice(6).tointeger());
		local down = false;
		if (victim != null && GxLdBot.IsAlive(victim)) {
			try { down = victim.IsIncapacitated() || victim.IsHangingFromLedge(); } catch (e) {}
		}
		if (!down) {
			release.append(key);
			continue;
		}
		result = victim;
	}
	foreach (i, k in release) {
		if (k in GxLdBot.Claims && GxLdBot.Claims[k].owner == idx) {
			delete GxLdBot.Claims[k];
		}
	}
	return result;
}

// A guard spot near a downed victim: between the victim and the nearest threat,
// or just on the victim if it is calm.
function GxLdBot::CoverGuardPos(victim) {
	local vo = null;
	try { vo = victim.GetOrigin(); } catch (e) { return null; }
	local threat = GxLdBot.NearestThreatNear(victim, 900.0, 1500.0);
	if (GxLdBot.IsValidEntity(threat)) {
		try {
			local dir = threat.GetOrigin() - vo;
			local len = dir.Length();
			if (len > 1.0) {
				return vo + dir.Scale(GxLdBot.Settings.CoverGuardDistance / len);
			}
		} catch (e2) {}
	}
	return vo;
}

// Pick a close common to help clear only when a survivor is actually being
// swarmed. This is intentionally narrow: short attack bursts, no movement, and
// the arbiter resets the bot back to vanilla when the burst ends.
function GxLdBot::AssistTargetFor(bot) {
	if (!GxLdBot.Settings.EnableAssist || !GxLdBot.IsValidEntity(bot)) {
		return null;
	}
	local profile = GxLdBot.GetProfile(bot);
	local assistRadius = GxLdBot.Settings.AssistCommonRadius;
	local assistCount = GxLdBot.Settings.AssistCommonCount;
	local assistMax = GxLdBot.Settings.AssistMaxDistance;
	if (profile != null) {
		if ("cardAssistRadiusAdd" in profile) {
			assistRadius += profile.cardAssistRadiusAdd;
		}
		if ("cardAssistCountAdd" in profile) {
			assistCount += profile.cardAssistCountAdd;
		}
		if ("cardAssistMaxAdd" in profile) {
			assistMax += profile.cardAssistMaxAdd;
		}
	}
	if (("TeamEmergency" in GxLdBot) && GxLdBot.TeamEmergency()) {
		assistRadius = assistRadius * GxLdBot.Settings.EmergencyAssistMultiplier;
		assistMax = assistMax * GxLdBot.Settings.EmergencyAssistMultiplier;
		assistCount = assistCount / 2;
	}
	if (assistRadius < 120.0) {
		assistRadius = 120.0;
	}
	if (assistCount < 1) {
		assistCount = 1;
	}
	if (assistMax < 300.0) {
		assistMax = 300.0;
	}

	local botOrigin = null;
	try {
		botOrigin = bot.GetOrigin();
	} catch (e) {
		return null;
	}

	local best = { ent = null, score = 999999.0 };
	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s)) {
			return;
		}

		local origin = null;
		try {
			origin = s.GetOrigin();
			if ((botOrigin - origin).Length() > assistMax) {
				return;
			}
		} catch (e) {
			return;
		}

		local special = GxLdBot.NearestThreatNear(s, 0.0, assistRadius * 2.0);
		if (special != null) {
			local spScore = 999999.0;
			try {
				spScore = (botOrigin - special.GetOrigin()).Length() - 160.0;
			} catch (es) {}
			if (spScore < best.score) {
				best.ent = special;
				best.score = spScore;
			}
			return;
		}

		local commons = GxLdBot.CountCommonsAround(origin, assistRadius);
		if (commons < assistCount) {
			return;
		}

		local target = GxLdBot.NearestCommonAround(origin, assistRadius);
		if (target == null) {
			return;
		}

		local score = 999999.0;
		try {
			score = (botOrigin - target.GetOrigin()).Length() - (commons * 18.0);
		} catch (e2) {}
		if (score < best.score) {
			best.ent = target;
			best.score = score;
		}
	});

	return best.ent;
}

function GxLdBot::EmergencyDefendIntentFor(bot) {
	if (!GxLdBot.IsValidEntity(bot) || !("HumanEmergencyVictim" in GxLdBot)) {
		return null;
	}
	local victim = GxLdBot.HumanEmergencyVictim();
	if (victim == null || !GxLdBot.IsAlive(victim)) {
		return null;
	}
	if (GxLdBot.DistanceBetween(bot, victim) > GxLdBot.Settings.EmergencyThreatRadius) {
		return null;
	}

	local pin = GxLdBot.PinnedSpecialOf(victim);
	if (pin != null && GxLdBot.IsValidEntity(pin.special)) {
		return { victim = victim, target = pin.special, reason = "pin" };
	}

	local threat = GxLdBot.NearestThreatNear(victim,
		GxLdBot.Settings.EmergencyCommonRadius,
		GxLdBot.Settings.EmergencyThreatRadius);
	if (threat == null) {
		return null;
	}
	return { victim = victim, target = threat, reason = "down" };
}

function GxLdBot::EscortIntentFor(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return null;
	}
	local human = GxLdBot.NearestHuman(bot);
	if (human == null || !GxLdBot.IsAlive(human)) {
		return null;
	}
	if (("TeamUnderStress" in GxLdBot) && GxLdBot.TeamUnderStress()) {
		return null;
	}
	local threshold = GxLdBot.Settings.EscortCatchupDistance;
	local profile = GxLdBot.GetProfile(bot);
	if (profile != null && "followDistance" in profile) {
		local personal = profile.followDistance + 140.0;
		if (personal > threshold) {
			threshold = personal;
		}
	}
	if (threshold > GxLdBot.Settings.MaxSeparation) {
		threshold = GxLdBot.Settings.MaxSeparation;
	}
	if (GxLdBot.DistanceBetween(bot, human) <= threshold) {
		return null;
	}
	local pos = null;
	try { pos = human.GetOrigin(); } catch (e) { return null; }
	return { pos = pos, human = human };
}

function GxLdBot::IdleWanderPos(bot, human) {
	if (!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(human)) {
		return null;
	}
	local origin = null;
	try { origin = human.GetOrigin(); } catch (e) { return null; }
	local idx = 0;
	try { idx = bot.GetEntityIndex(); } catch (e2) {}
	local step = (GxLdBot.Now() / 3.0).tointeger();
	local angle = (idx * 1.71) + (step * 2.13);
	local radius = GxLdBot.Settings.IdleWanderRadius * (0.55 + ((idx % 3) * 0.18));
	return Vector(
		origin.x + cos(angle) * radius,
		origin.y + sin(angle) * radius,
		origin.z
	);
}

// ---- intent selection -------------------------------------------------------

function GxLdBot::ComputeIntent(bot, idx, now) {
	// 1) rescue
	if (GxLdBot.Settings.EnableRescue) {
		local r = GxLdBot.RescueVictimFor(bot);
		if (r != null) {
			return { kind = "rescue", info = r };
		}
	}

	// 2) emergency defend: if a human is pinned/incapped, immediately attack the
	// threat near them (Witch / special / close commons) instead of watching.
	local defend = GxLdBot.EmergencyDefendIntentFor(bot);
	if (defend != null) {
		return { kind = "defend", info = defend };
	}

	// 3) retreat — continue an active burst, else maybe start a new one
	if (GxLdBot.Settings.EnableRetreat) {
		if (idx in GxLdBot.Action && GxLdBot.Action[idx].kind == "retreat") {
			if (now < GxLdBot.Action[idx].until) {
				local t = GxLdBot.NearestThreatNear(bot,
					GxLdBot.Settings.RetreatCommonRadius, GxLdBot.Settings.RetreatCommonRadius * 2.0);
				if (t != null) {
					return { kind = "retreat", threat = t };
				}
			}
			// burst finished (or threat gone): start cooldown and fall through
			GxLdBot.SetTableSlot(GxLdBot.RetreatCooldownUntil, idx,
				now + GxLdBot.Settings.RetreatCooldown);
		}
		local onCd = (idx in GxLdBot.RetreatCooldownUntil) && (now < GxLdBot.RetreatCooldownUntil[idx]);
		if (!onCd && GxLdBot.ShouldRetreat(bot)) {
			local t2 = GxLdBot.NearestThreatNear(bot,
				GxLdBot.Settings.RetreatCommonRadius, GxLdBot.Settings.RetreatCommonRadius * 2.0);
			if (t2 != null) {
				return { kind = "retreat", threat = t2 };
			}
		}
	}

	// 4) cover
	if (GxLdBot.Settings.EnableCover) {
		local v = GxLdBot.CoverVictimFor(bot);
		if (v != null) {
			return { kind = "cover", victim = v };
		}
	}

	// 5) heal self: start only when safe, then commit long enough to finish.
	if (GxLdBot.Settings.EnableHeal && GxLdBot.HealShouldContinue(bot, idx, now)) {
		return { kind = "heal" };
	}
	if (GxLdBot.Settings.EnableHeal && GxLdBot.HealIntentFor(bot)) {
		return { kind = "heal" };
	}

	// 6) frequent close-threat shove (right click) before optional movement.
	local shoveTarget = GxLdBot.CombatShoveTargetFor(bot, idx, now);
	if (shoveTarget != null) {
		return { kind = "shove", target = shoveTarget };
	}

	// 7) catch up to the human before doing optional pressure actions.
	local escort = GxLdBot.EscortIntentFor(bot);
	if (escort != null) {
		return { kind = "escort", pos = escort.pos, human = escort.human };
	}

	// 8) close-horde assist: short attack bursts to help clear swarmed teammates
	if (GxLdBot.Settings.EnableAssist) {
		if (idx in GxLdBot.Action && GxLdBot.Action[idx].kind == "assist") {
			local a = GxLdBot.Action[idx];
			if (now < a.until && "target" in a && GxLdBot.IsValidEntity(a.target)) {
				return { kind = "assist", target = a.target };
			}
		}
		local assistTarget = GxLdBot.AssistTargetFor(bot);
		if (assistTarget != null) {
			return { kind = "assist", target = assistTarget };
		}
	}

	// 9) progress / scout (path clear). Flow-based map
	// advancement (progress.nut) is tried first so bots push toward the actual
	// objective; the old human-relative scout is a fallback for maps with no
	// usable flow (finales / survival).
	if ("ProgressIntentFor" in GxLdBot) {
		local ppos = GxLdBot.ProgressIntentFor(bot);
		if (ppos != null) {
			return { kind = "progress", pos = ppos };
		}
	}
	local spos = GxLdBot.ScoutIntentFor(bot);
	if (spos != null) {
		return { kind = "scout", pos = spos };
	}

	// 10) idle (calm stall) — reuses social's decision
	local human = GxLdBot.IdleIntentFor(bot);
	if (human != null) {
		return { kind = "idle", human = human };
	}

	return null;
}

// ---- enactment --------------------------------------------------------------

// Issue/refresh a move command with light dampening so we don't spam CommandABot
// every tick for an unchanged destination. Returns the action record.
function GxLdBot::IssueMoveIntent(bot, idx, kind, pos, faceEnt, now) {
	local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
	local reissue = false;
	if (a != null && a.kind != kind) {
		GxLdBot.EndAction(bot, idx, true);
		a = null;
	}
	if (a == null) {
		a = { kind = kind, since = now, until = 0.0, ready = 0.0,
			target = faceEnt, pos = null, movedAt = 0.0, holding = false, claimKey = null };
		GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
		if (kind == "progress") {
			GxLdBot.Notify("action:progress:" + idx,
				GxLdBot.SafeName(bot) + " pushing forward", 12.0);
		} else if (kind == "scout") {
			GxLdBot.Notify("action:scout:" + idx,
				GxLdBot.SafeName(bot) + " scouting ahead", 12.0);
		}
		reissue = true;
	} else {
		local far = true;
		try { far = (a.pos == null) || ((a.pos - pos).Length() > 120.0); } catch (e) { far = true; }
		if (far || (now - a.movedAt) > 1.5) {
			reissue = true;
		}
	}
	if (reissue) {
		GxLdBot.BotMoveTo(bot, pos);
		a.pos = pos;
		a.movedAt = now;
	}
	a.target = faceEnt;
	GxLdBot.ClearShove(bot);
	return a;
}

function GxLdBot::EnactIntent(bot, idx, intent, now) {
	if (intent.kind == "defend") {
		local info = intent.info;
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "defend") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			a = { kind = "defend", since = now, until = now + 1.2,
				ready = 0.0, target = info.target, pos = null, movedAt = 0.0, holding = false, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.Log("defend " + GxLdBot.SafeName(bot) +
				" victim=" + GxLdBot.SafeName(info.victim) +
				" target=" + GxLdBot.SafeName(info.target) +
				" reason=" + info.reason, true);
			GxLdBot.Notify("action:defend:" + idx,
				GxLdBot.SafeName(bot) + " defending " + GxLdBot.SafeName(info.victim), 3.0);
		}
		a.target = info.target;
		a.until = now + 1.2;
		GxLdBot.ClearShove(bot);
		GxLdBot.ClearHeal(bot);
		GxLdBot.BotAttackTarget(bot, info.target);
		return;
	}

	if (intent.kind == "heal") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "heal") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			a = { kind = "heal", since = now, until = now + GxLdBot.Settings.HealDuration,
				ready = 0.0, target = null, pos = null, movedAt = 0.0, holding = false, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.Log("heal " + GxLdBot.SafeName(bot));
			GxLdBot.Notify("action:heal:" + idx, GxLdBot.SafeName(bot) + " healing up", 6.0);
		}
		if (!GxLdBot.HealShouldContinue(bot, idx, now)) {
			GxLdBot.EndAction(bot, idx, true);
			return;
		}
		try {
			local b = NetProps.GetPropInt(bot, "m_afButtonForced");
			if ((b & GxLdBot.BTN_USE) == 0) {
				NetProps.SetPropInt(bot, "m_afButtonForced", b | GxLdBot.BTN_USE);
			}
		} catch (e) {}
		GxLdBot.ClearShove(bot);
		return;
	}

	if (intent.kind == "shove") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "shove") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			local duration = GxLdBot.Settings.CombatShoveDuration;
			a = { kind = "shove", since = now, until = now + duration,
				ready = 0.0, target = intent.target, pos = null, movedAt = 0.0, holding = false, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.SetTableSlot(GxLdBot.ShoveCooldownUntil, idx,
				now + duration + GxLdBot.Settings.CombatShoveCooldown);
		}
		a.target = intent.target;
		GxLdBot.ClearHeal(bot);
		GxLdBot.SetShove(bot, intent.target);
		return;
	}

	if (intent.kind == "rescue") {
		local info = intent.info;
		local key = "rescue:" + info.victim.GetEntityIndex();
		GxLdBot.TryClaim(key, bot); // re-affirm freshness so the claim won't expire mid-rescue

		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "rescue") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			GxLdBot.BotResetCommand(bot); // cancel any prior order before committing
			a = { kind = "rescue", since = now, ready = now + GxLdBot.ComputeRescueDelay(bot),
				until = 0.0, target = info.victim, pos = null, movedAt = 0.0, holding = false, claimKey = key };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.SetFocus(bot, info.victim, "rescue");
			GxLdBot.Log("rescue commit " + GxLdBot.SafeName(bot) +
				" victim=" + GxLdBot.SafeName(info.victim) + " delay=" + (a.ready - now));
			GxLdBot.Notify("action:rescue:" + idx,
				GxLdBot.SafeName(bot) + " scripted rescue -> " +
				GxLdBot.SafeName(info.victim), 4.0);
		}
		a.target = info.victim;
		a.claimKey = key;

		if (now < a.ready) {
			GxLdBot.ClearShove(bot); // hesitation window: do nothing (vanilla also helps)
			return;
		}

		local inShoveRange = false;
		try {
			inShoveRange = (bot.GetOrigin() - info.victim.GetOrigin()).Length() <= GxLdBot.Settings.RescueShoveRange;
		} catch (e) {}

		if (GxLdBot.Settings.EnableShove && info.shovable && inShoveRange) {
			GxLdBot.SetShove(bot, info.special);
		} else {
			GxLdBot.ClearShove(bot);
			GxLdBot.BotAttackTarget(bot, info.special);
		}
		return;
	}

	if (intent.kind == "retreat") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "retreat") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			local duration = GxLdBot.Settings.RetreatDuration;
			local profile = GxLdBot.GetProfile(bot);
			if (profile != null && "cardRetreatDurationMul" in profile) {
				duration = duration * profile.cardRetreatDurationMul;
			}
			if (duration < 0.15) {
				duration = 0.15;
			}
			a = { kind = "retreat", since = now, until = now + duration,
				ready = 0.0, target = intent.threat, pos = null, movedAt = 0.0, holding = false, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.Log("retreat " + GxLdBot.SafeName(bot));
			GxLdBot.Notify("action:retreat:" + idx,
				GxLdBot.SafeName(bot) + " retreating from pressure", 4.0);
		}
		a.target = intent.threat;
		GxLdBot.ClearShove(bot);
		GxLdBot.BotRetreatFrom(bot, intent.threat);
		return;
	}

	if (intent.kind == "cover") {
		local victim = intent.victim;
		local key = "cover:" + victim.GetEntityIndex();
		GxLdBot.TryClaim(key, bot);

		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "cover") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			a = { kind = "cover", since = now, until = 0.0, ready = 0.0,
				target = victim, pos = null, movedAt = 0.0, holding = false, claimKey = key };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.SetFocus(bot, victim, "cover");
			GxLdBot.Log("cover " + GxLdBot.SafeName(bot) + " victim=" + GxLdBot.SafeName(victim));
			GxLdBot.Notify("action:cover:" + idx,
				GxLdBot.SafeName(bot) + " covering " + GxLdBot.SafeName(victim), 5.0);
		}
		a.target = victim;
		a.claimKey = key;
		GxLdBot.ClearShove(bot);

		local guardPos = GxLdBot.CoverGuardPos(victim);
		local near = false;
		try { near = (guardPos != null) && ((bot.GetOrigin() - guardPos).Length() <= GxLdBot.Settings.CoverGuardDistance); } catch (e) {}
		if (near) {
			if (!a.holding) { // arrived: stop and let vanilla shoot from the guard spot
				GxLdBot.BotResetCommand(bot);
				a.holding = true;
			}
		} else {
			a.holding = false;
			local far = true;
			try { far = (a.pos == null) || ((a.pos - guardPos).Length() > 120.0); } catch (e2) { far = true; }
			if (far || (now - a.movedAt) > 1.5) {
				GxLdBot.BotMoveTo(bot, guardPos);
				a.pos = guardPos;
				a.movedAt = now;
			}
		}
		return;
	}

	if (intent.kind == "assist") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "assist") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			local duration = GxLdBot.Settings.AssistDuration;
			local profile = GxLdBot.GetProfile(bot);
			if (profile != null && "cardAssistDurationAdd" in profile) {
				duration += profile.cardAssistDurationAdd;
			}
			if (duration < 0.2) {
				duration = 0.2;
			}
			a = { kind = "assist", since = now, until = now + duration,
				ready = 0.0, target = intent.target, pos = null, movedAt = 0.0, holding = false, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			GxLdBot.Log("assist " + GxLdBot.SafeName(bot) + " target=" + GxLdBot.SafeName(intent.target));
			GxLdBot.Notify("action:assist:" + idx,
				GxLdBot.SafeName(bot) + " clearing close horde", 5.0);
		} else if (now >= a.until || a.target != intent.target) {
			a.since = now;
			local duration = GxLdBot.Settings.AssistDuration;
			local profile = GxLdBot.GetProfile(bot);
			if (profile != null && "cardAssistDurationAdd" in profile) {
				duration += profile.cardAssistDurationAdd;
			}
			if (duration < 0.2) {
				duration = 0.2;
			}
			a.until = now + duration;
		}
		a.target = intent.target;
		GxLdBot.ClearShove(bot);
		GxLdBot.BotAttackTarget(bot, intent.target);
		return;
	}

	if (intent.kind == "progress") {
		GxLdBot.IssueMoveIntent(bot, idx, "progress", intent.pos, null, now);
		return;
	}

	if (intent.kind == "scout") {
		GxLdBot.IssueMoveIntent(bot, idx, "scout", intent.pos, null, now);
		return;
	}

	if (intent.kind == "escort") {
		GxLdBot.IssueMoveIntent(bot, idx, "escort", intent.pos, intent.human, now);
		return;
	}

	if (intent.kind == "idle") {
		local human = intent.human;
		local pos = null;
		pos = GxLdBot.IdleWanderPos(bot, human);
		if (pos == null) {
			try { pos = human.GetOrigin(); } catch (e) {}
		}
		if (pos == null) {
			GxLdBot.EndAction(bot, idx, true);
			return;
		}
		GxLdBot.IssueMoveIntent(bot, idx, "idle", pos, human, now);
		GxLdBot.FaceEntity(bot, human);
		GxLdBot.IdleSpeak(bot, human); // logs only; idle does not force voice lines
		return;
	}
}

// Drop a bot's action: release any claim it owned, clear a stuck shove, and
// (on a real state transition) reset it to vanilla so no stale command lingers.
function GxLdBot::EndAction(bot, idx, doReset) {
	if (idx in GxLdBot.Action) {
		local a = GxLdBot.Action[idx];
		if ("claimKey" in a && a.claimKey != null) {
			try {
				if (a.claimKey in GxLdBot.Claims && GxLdBot.Claims[a.claimKey].owner == idx) {
					delete GxLdBot.Claims[a.claimKey];
				}
			} catch (e) {}
		}
		delete GxLdBot.Action[idx];
	}
	GxLdBot.ClearShove(bot);
	GxLdBot.ClearHeal(bot);
	if (doReset) {
		GxLdBot.BotResetCommand(bot);
	}
}

function GxLdBot::ClearAllActions(doReset) {
	local indices = [];
	foreach (idx, a in GxLdBot.Action) {
		indices.append(idx);
	}
	foreach (i, idx in indices) {
		local bot = GxLdBot.SurvivorByIndex(idx);
		if (bot != null) {
			GxLdBot.EndAction(bot, idx, doReset);
		} else {
			delete GxLdBot.Action[idx];
		}
	}
	GxLdBot.ForEachSurvivorBot(function(b) {
		GxLdBot.ClearShove(b);
		GxLdBot.ClearHeal(b);
	});
}

// ---- the arbiter tick -------------------------------------------------------

function GxLdBot::ActionArbiterTick() {
	if (GxLdBot.Sleeping || GxLdBot.UpdateSleepState()) {
		return;
	}
	if (!GxLdBot.Settings.EnableActions) {
		if (!GxLdBot.ActionDisabledCleaned) {
			GxLdBot.ClearAllActions(true);
			GxLdBot.ActionDisabledCleaned = true;
			GxLdBot.Log("actions disabled: reset all bot commands", true);
		}
		return;
	}
	GxLdBot.ActionDisabledCleaned = false;
	local now = GxLdBot.Now();

	GxLdBot.AssignRescues(now);
	GxLdBot.AssignCover(now);

	GxLdBot.ForEachSurvivorBot(function(bot) {
		local idx = bot.GetEntityIndex();

		if (!GxLdBot.IsAlive(bot)) {
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, false); // can't command a dead bot, just release state
			}
			return;
		}

		if (GxLdBot.IsUncommandable(bot)) {
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, true);
			} else {
				GxLdBot.ClearShove(bot);
			}
			return;
		}

		local intent = GxLdBot.ComputeIntent(bot, idx, now);
		if (intent == null) {
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, true); // transition to vanilla — reset ONCE
			} else {
				GxLdBot.ClearShove(bot);
			}
			return;
		}

		GxLdBot.EnactIntent(bot, idx, intent, now);
	});
}

function GxLdBot::PrintActions(player) {
	local any = false;
	foreach (idx, a in GxLdBot.Action) {
		any = true;
		local tgt = ("target" in a && a.target != null && GxLdBot.IsValidEntity(a.target))
			? GxLdBot.SafeName(a.target) : "-";
		GxLdBot.Chat(player, "idx=" + idx + " action=" + a.kind +
			" target=" + tgt + " for=" + (GxLdBot.Now() - a.since) + "s");
	}
	if (!any) {
		GxLdBot.Chat(player, "no active bot actions (all on vanilla AI)");
	}
}

// ---- think entity (faster than the 1Hz planning loop, for crisp assists) ----

function GxLdBot::ArbiterThink() {
	GxLdBot.SafeCall("arbiter", function() {
		GxLdBot.ActionArbiterTick();
	});
	return GxLdBot.Settings.ArbiterInterval;
}

function GxLdBot::StartArbiterThink() {
	if (GxLdBot.ArbiterEntity != null && GxLdBot.IsValidEntity(GxLdBot.ArbiterEntity)) {
		return;
	}
	try {
		local ent = SpawnEntityFromTable("info_target", { targetname = "gxldbot_arbiter" });
		if (ent == null) {
			GxLdBot.Log("failed to create arbiter entity", true);
			return;
		}
		ent.ValidateScriptScope();
		local scope = ent.GetScriptScope();
		scope["gxldbot_arbiter"] <- function() {
			return ::GxLdBot.ArbiterThink();
		};
		AddThinkToEnt(ent, "gxldbot_arbiter");
		GxLdBot.ArbiterEntity = ent;
		GxLdBot.Log("arbiter think started", true);
	} catch (e) {
		GxLdBot.Log("StartArbiterThink failed: " + e, true);
	}
}

// ---- registration -----------------------------------------------------------
// The arbiter runs on its own ~0.18s think entity (started here and re-ensured
// by main.StartThink). On round start, clear all action/cooldown state and drop
// any forced shove bits, then make sure the think entity exists.

GxLdBot.RegisterRound("actions_reset", function() {
	GxLdBot.Action = {};
	GxLdBot.RetreatCooldownUntil = {};
	GxLdBot.ShoveCooldownUntil = {};
	GxLdBot.ActionDisabledCleaned = false;
	GxLdBot.ForEachSurvivorBot(function(b) {
		GxLdBot.ClearShove(b);
		GxLdBot.ClearHeal(b);
	});
	GxLdBot.StartArbiterThink();
});
