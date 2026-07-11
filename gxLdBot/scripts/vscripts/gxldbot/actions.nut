// gxLdBot actions module: the single Action Arbiter (0.3 real-behavior layer).
//
// This module is the ONE place allowed to issue CommandABot / forced buttons to
// a survivor bot. Every tick (its own ~0.18s think entity) it picks the single
// highest-priority intent per bot and enacts it; when no intent applies it hands
// the bot back to the vanilla engine with BOT_CMD_RESET. General combat mostly
// stays vanilla; 0.4 adds only a narrow close-horde assist attack burst.
//
// SURVIVAL lane remains hard-priority: rescue > defend > retreat > cover >
// heal > shove. TEAM / EXPRESSION candidates then compete by utility, slot and
// short minimum holds. Rescue remains off by default so vanilla owns it.
//
// Enactment primitives are all verified against the shipped Advanced Bot AI mod:
//   CommandABot cmd 0/1/2/3, m_afButtonForced shove, SnapEyeAngles aim,
//   m_iShovePenalty / m_flNextSecondaryAttack shove reset, pin NetProps.

if (!("ShoveCooldownUntil" in GxLdBot)) {
	GxLdBot.ShoveCooldownUntil <- {};
}

// ---- low-level enact primitives --------------------------------------------

function GxLdBot::GetActuatorLease(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return null;
	}
	local idx = bot.GetEntityIndex();
	if (!(idx in GxLdBot.ActuatorLease)) {
		GxLdBot.ActuatorLease[idx] <- {
			commandOwned = false,
			commandKind = "none",
			forcedBits = 0,
			speedOwned = false,
			speedValue = 1.0,
			updatedAt = GxLdBot.Now()
		};
	}
	local lease = GxLdBot.ActuatorLease[idx];
	// Hot reload/back-compat: leases created by an older include may not yet have
	// the speed fields, so extend them before any reader touches the slots.
	if (!("speedOwned" in lease)) { lease.speedOwned <- false; }
	if (!("speedValue" in lease)) { lease.speedValue <- 1.0; }
	return lease;
}

function GxLdBot::LeaseCommand(bot, kind) {
	local lease = GxLdBot.GetActuatorLease(bot);
	if (lease == null) { return; }
	lease.commandOwned = true;
	lease.commandKind = kind;
	lease.updatedAt = GxLdBot.Now();
}

function GxLdBot::ReleaseCommandLease(bot) {
	if (!GxLdBot.IsValidEntity(bot)) { return; }
	local idx = bot.GetEntityIndex();
	if (!(idx in GxLdBot.ActuatorLease)) { return; }
	local lease = GxLdBot.ActuatorLease[idx];
	lease.commandOwned = false;
	lease.commandKind = "none";
	lease.updatedAt = GxLdBot.Now();
}

function GxLdBot::LeaseForcedBit(bot, bit) {
	local lease = GxLdBot.GetActuatorLease(bot);
	if (lease == null) { return; }
	lease.forcedBits = lease.forcedBits | bit;
	lease.updatedAt = GxLdBot.Now();
}

function GxLdBot::ReleaseForcedBit(bot, bit) {
	if (!GxLdBot.IsValidEntity(bot)) { return; }
	local idx = bot.GetEntityIndex();
	if (!(idx in GxLdBot.ActuatorLease)) { return; }
	local lease = GxLdBot.ActuatorLease[idx];
	lease.forcedBits = lease.forcedBits & ~bit;
	lease.updatedAt = GxLdBot.Now();
}

// Own m_flLaggedMovementValue only while gxLdBot has actually raised it. The
// engine also uses this prop for slow effects, so the driver never writes while
// the observed value is below 1.0 and never claims a value it did not author.
function GxLdBot::LeaseMovementBoost(bot, target) {
	if (!GxLdBot.IsValidEntity(bot) || target <= 1.0 ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
	}
	local lease = GxLdBot.GetActuatorLease(bot);
	if (lease == null) { return false; }
	local cur = 1.0;
	try { cur = NetProps.GetPropFloat(bot, "m_flLaggedMovementValue"); }
	catch (e) { return false; }

	// A value below 1.0 belongs to an engine slowdown. Drop any stale ownership
	// record and leave the value completely untouched.
	if (cur < 0.99) {
		lease.speedOwned = false;
		lease.speedValue = 1.0;
		return false;
	}
	if (lease.speedOwned) {
		local authoredDelta = cur - lease.speedValue;
		if (authoredDelta < 0.0) { authoredDelta = -authoredDelta; }
		if (authoredDelta > 0.03) {
			// Another system changed the prop after our write; no longer ours to restore.
			lease.speedOwned = false;
			lease.speedValue = 1.0;
		}
	}
	// Boost path only raises. A smaller desired boost waits until the lease is
	// released at the near threshold instead of writing downward over engine state.
	if (cur >= target - 0.01) {
		return lease.speedOwned;
	}
	try {
		NetProps.SetPropFloat(bot, "m_flLaggedMovementValue", target);
		lease.speedOwned = true;
		lease.speedValue = target;
		lease.updatedAt = GxLdBot.Now();
		return true;
	} catch (e2) {
		GxLdBot.Log("movement boost failed: " + e2, true);
	}
	return false;
}

function GxLdBot::ReleaseMovementBoost(bot, reason = "speed_release") {
	if (!GxLdBot.IsValidEntity(bot)) { return; }
	local idx = bot.GetEntityIndex();
	if (!(idx in GxLdBot.ActuatorLease)) { return; }
	local lease = GxLdBot.ActuatorLease[idx];
	if (!("speedOwned" in lease) || !lease.speedOwned) { return; }
	local cur = 1.0;
	local readable = true;
	try { cur = NetProps.GetPropFloat(bot, "m_flLaggedMovementValue"); }
	catch (e) { readable = false; }
	if (readable) {
		local authoredDelta = cur - lease.speedValue;
		if (authoredDelta < 0.0) { authoredDelta = -authoredDelta; }
		// Restore only the exact boost we own. If the engine slowed the bot or any
		// other system changed the value, clearing the lease is the only safe action.
		if (cur > 1.0 && authoredDelta <= 0.03) {
			try { NetProps.SetPropFloat(bot, "m_flLaggedMovementValue", 1.0); }
			catch (e2) { GxLdBot.Log("movement boost release failed: " + e2, true); }
		}
	}
	lease.speedOwned = false;
	lease.speedValue = 1.0;
	lease.updatedAt = GxLdBot.Now();
}

function GxLdBot::ReleaseAllMovementBoosts(reason = "speed_release_all") {
	local indices = [];
	foreach (idx, lease in GxLdBot.ActuatorLease) {
		if (("speedOwned" in lease) && lease.speedOwned) { indices.append(idx); }
	}
	foreach (i, idx in indices) {
		try {
			local ent = EntIndexToHScript(idx);
			if (ent != null && GxLdBot.IsValidEntity(ent)) {
				GxLdBot.ReleaseMovementBoost(ent, reason);
			}
		} catch (e) {}
	}
}

function GxLdBot::BotAttackTarget(bot, target) {
	if (!("CommandABot" in getroottable()) ||
			!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(target) ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
	}
	local idx = bot.GetEntityIndex();
	local targetIdx = target.GetEntityIndex();
	local now = GxLdBot.Now();
	if (idx in GxLdBot.LastAttack) {
		local last = GxLdBot.LastAttack[idx];
		if (last.targetIdx == targetIdx &&
				(now - last.at) < GxLdBot.Settings.AttackCommandRefresh) {
			GxLdBot.LeaseCommand(bot, "attack");
			return true;
		}
	}
	try {
		CommandABot({ cmd = 0, target = target, bot = bot });
		GxLdBot.SetTableSlot(GxLdBot.LastAttack, idx, { targetIdx = targetIdx, at = now });
		GxLdBot.LeaseCommand(bot, "attack");
		return true;
	} catch (e) {
		GxLdBot.Log("BotAttackTarget failed: " + e, true);
	}
	return false;
}

function GxLdBot::BotMoveTo(bot, pos) {
	if (!("CommandABot" in getroottable()) || !GxLdBot.IsValidEntity(bot) || pos == null ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
	}
	try {
		CommandABot({ cmd = 1, pos = pos, bot = bot });
		GxLdBot.LeaseCommand(bot, "move");
		return true;
	} catch (e) {
		GxLdBot.Log("BotMoveTo failed: " + e, true);
	}
	return false;
}

function GxLdBot::BotRetreatFrom(bot, threat) {
	if (!("CommandABot" in getroottable()) ||
			!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(threat) ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
	}
	try {
		CommandABot({ cmd = 2, target = threat, bot = bot });
		GxLdBot.LeaseCommand(bot, "retreat");
		return true;
	} catch (e) {
		GxLdBot.Log("BotRetreatFrom failed: " + e, true);
	}
	return false;
}

// Hand a bot back to the engine's own AI: BOT_CMD_RESET (3) cancels any move /
// attack order we issued. The arbiter calls this whenever it drops an action so
// a bot is never left executing a stale command.
function GxLdBot::BotResetCommand(bot) {
	if (!("CommandABot" in getroottable()) || !GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	try {
		CommandABot({ cmd = 3, bot = bot });
		local idx = bot.GetEntityIndex();
		if (idx in GxLdBot.LastAttack) { delete GxLdBot.LastAttack[idx]; }
		GxLdBot.ReleaseCommandLease(bot);
		GxLdBot.Log("reset " + GxLdBot.SafeName(bot));
		return true;
	} catch (e) {
		GxLdBot.Log("BotResetCommand failed: " + e, true);
	}
	return false;
}

// Snap a bot's aim toward a target. Used only as a single nudge right before a
// shove / during idle facing — never a continuous per-frame aim takeover (that
// is the "superhuman aim" the design avoids). Mirrors the reference's QAngle
// math (ai_utils.nut CreateQAngle).
function GxLdBot::FaceEntity(bot, target) {
	if (!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(target) ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
	}
	try {
		local d = target.GetOrigin() - bot.EyePosition();
		local yaw = atan2(d.y, d.x) * 180.0 / PI;
		local flat = sqrt(d.x * d.x + d.y * d.y);
		local pitch = atan2(-d.z, flat) * 180.0 / PI;
		bot.SnapEyeAngles(QAngle(pitch, yaw, 0));
		return true;
	} catch (e) {
		GxLdBot.Log("FaceEntity failed: " + e, true);
	}
	return false;
}

function GxLdBot::FacePosition(bot, pos) {
	if (!GxLdBot.IsValidEntity(bot) || pos == null ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) { return false; }
	try {
		local d = pos - bot.EyePosition();
		local yaw = atan2(d.y, d.x) * 180.0 / PI;
		local flat = sqrt(d.x * d.x + d.y * d.y);
		local pitch = atan2(-d.z, flat) * 180.0 / PI;
		bot.SnapEyeAngles(QAngle(pitch, yaw, 0));
		return true;
	} catch (e) { GxLdBot.Log("FacePosition failed: " + e, true); }
	return false;
}

// Hold the shove button so the bot shoves a special off a pinned teammate. We
// zero the shove penalty + secondary-attack timer each tick so repeated shoves
// land (matching ai-shoveinfected.nut), and face the target first. The bit is
// cleared by ClearShove whenever the bot is not shoving, so it never sticks.
function GxLdBot::SetShove(bot, target) {
	if (!GxLdBot.IsValidEntity(bot) ||
			(("CanControlBots" in GxLdBot) && !GxLdBot.CanControlBots())) {
		return false;
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
		GxLdBot.LeaseForcedBit(bot, GxLdBot.BTN_SHOVE);
		return true;
	} catch (e3) {
		GxLdBot.Log("SetShove failed: " + e3, true);
	}
	return false;
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
	GxLdBot.ReleaseForcedBit(bot, GxLdBot.BTN_SHOVE);
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
	GxLdBot.ReleaseForcedBit(bot, GxLdBot.BTN_USE);
}

// Release the forced crouch bit used by the goof-off teabag. Called whenever a
// bot leaves idle (or any non-goof action) so the duck never sticks — a bot
// left stuck crouched would be a visible, immersion-breaking bug.
function GxLdBot::ClearGoof(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return;
	}
	try {
		local b = NetProps.GetPropInt(bot, "m_afButtonForced");
		if ((b & GxLdBot.BTN_DUCK) != 0) {
			NetProps.SetPropInt(bot, "m_afButtonForced", b & ~GxLdBot.BTN_DUCK);
		}
	} catch (e) {}
	GxLdBot.ReleaseForcedBit(bot, GxLdBot.BTN_DUCK);
}

// DESIGN 6.3 goof-off: zero-physical-risk idle antics. When a bot is idling in a
// calm stall right next to the human with nothing else to do, it occasionally
// teabags (toggles the crouch bit) and keeps facing the human — the classic
// "bored teammate" tell. No shove (griefing risk), no movement change, no
// flashlight yet (that needs a verified NetProp). Purely visual; cannot pull the
// bot off the group or interrupt anyone. Returns true while an antic is running.
function GxLdBot::GoofTick(bot, idx, human, now, maxDist = null) {
	if (!GxLdBot.Settings.EnableGoof || !GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	// Only goof close to the human — a teabag nobody can see isn't worth it, and
	// keeping it near the human guarantees we never drift into an outlier. The
	// guide caller passes a wider maxDist (a scout holding its lead point is out
	// ahead at mid-distance, so the default idle radius would bail every time).
	if (human == null || !GxLdBot.IsValidEntity(human)) {
		return false;
	}
	local radius = (maxDist != null) ? maxDist : GxLdBot.Settings.GoofHumanRadius;
	if (GxLdBot.DistanceBetween(bot, human) > radius) {
		return false;
	}

	local g = (idx in GxLdBot.Goof) ? GxLdBot.Goof[idx] : null;
	if (g == null) {
		// First antic fires SOON after a bot settles into idle (0.5-2s), not after
		// the full 5-12s interval - otherwise idle rarely lasts long enough to ever
		// see a teabag (that was the "never see bots crouch" bug). Subsequent antics
		// use the normal Goof interval. A small per-bot random keeps them from all
		// firing on the exact same tick.
		g = { nextAt = now + GxLdBot.RandFloat(0.5, 2.0),
			until = 0.0, lastToggle = 0.0, ducked = false };
		GxLdBot.SetTableSlot(GxLdBot.Goof, idx, g);
		return false;
	}

	// Currently mid-antic: drive the teabag toggle until it expires.
	if (now < g.until) {
		if ((now - g.lastToggle) >= GxLdBot.Settings.GoofCrouchToggle) {
			g.lastToggle = now;
			try {
				local b = NetProps.GetPropInt(bot, "m_afButtonForced");
				g.ducked = ((b & GxLdBot.BTN_DUCK) == 0);
				if (g.ducked) {
					NetProps.SetPropInt(bot, "m_afButtonForced", b | GxLdBot.BTN_DUCK);
					GxLdBot.LeaseForcedBit(bot, GxLdBot.BTN_DUCK);
				} else {
					NetProps.SetPropInt(bot, "m_afButtonForced", b & ~GxLdBot.BTN_DUCK);
					GxLdBot.ReleaseForcedBit(bot, GxLdBot.BTN_DUCK);
				}
			} catch (e) {}
		}
		GxLdBot.FaceEntity(bot, human);
		return true;
	}

	// Antic finished: make sure the duck bit is released, then roll for the next.
	if (g.ducked) {
		GxLdBot.ClearGoof(bot);
		g.ducked = false;
	}

	// Shared team state gates when the squad may teabag as a group (DESIGN 10 #3).
	local team = ("GoofTeam" in GxLdBot) ? GxLdBot.GoofTeam : null;

	// JOIN-IN: if another bot just started an antic and we're inside the join
	// window, roll to teabag along with them — this is the "a couple bots do it
	// together" the player wanted. Join is NOT gated by the team cooldown (that's
	// what lets them sync); the cooldown only gates fresh group starts below.
	if (team != null && now < team.joinUntil &&
			GxLdBot.RandInt(1, 100) <= GxLdBot.Settings.GoofJoinChance) {
		g.until = now + GxLdBot.Settings.GoofDuration;
		g.lastToggle = 0.0;
		g.nextAt = now + GxLdBot.RandFloat(GxLdBot.Settings.GoofMinInterval,
			GxLdBot.Settings.GoofMaxInterval);
		GxLdBot.FaceEntity(bot, human);
		return true;
	}

	if (now >= g.nextAt) {
		g.nextAt = now + GxLdBot.RandFloat(GxLdBot.Settings.GoofMinInterval,
			GxLdBot.Settings.GoofMaxInterval);
		if (GxLdBot.RandInt(1, 100) <= GxLdBot.Settings.GoofChance) {
			// Fresh group start — gated by the team-wide cooldown so the whole
			// squad can't teabag constantly. Opening a start also opens the join
			// window so others can pile on for the next GoofJoinWindow seconds.
			if (team != null && (now - team.lastStart) < GxLdBot.Settings.GoofTeamCooldown) {
				return false; // squad on cooldown — skip this start, try again later
			}
			if (team != null) {
				team.lastStart = now;
				team.joinUntil = now + GxLdBot.Settings.GoofJoinWindow;
			}
			g.until = now + GxLdBot.Settings.GoofDuration;
			g.lastToggle = 0.0;
			GxLdBot.FaceEntity(bot, human);
			return true;
		}
	}
	return false;
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

	local record = GxLdBot.ThreatRecordFor(bot);
	if (record == null) { return null; }
	local special = GxLdBot.ThreatListTarget(record.specials,
		GxLdBot.Settings.CombatShoveSpecialRadius, 1);
	if (special != null && !("IsTank" in GxLdBot && GxLdBot.IsTank(special.ent))) {
		return special.ent;
	}

	// Commons: only shove when actually swarmed by REACHABLE commons. A lone common
	// is shot (vanilla), not shoved. Same-floor filtering is THE fix for "bot shoves
	// empty air" — the sphere test used to count zombies a floor above/below.
	local commons = GxLdBot.ThreatListTarget(record.commons,
		GxLdBot.Settings.CombatShoveRadius, GxLdBot.Settings.CombatShoveCommonCount);
	return (commons != null) ? commons.ent : null;
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
	// On a ladder (movetype 9 = MOVETYPE_LADDER): NEVER command. Issuing BotMoveTo
	// mid-climb interrupts the engine's ladder traversal and the bot drops off
	// partway up (the "climbs to the middle then falls" bug on vertical maps).
	// Hand ladder climbing entirely to vanilla.
	try { if (NetProps.GetPropInt(bot, "movetype") == 9) return true; } catch (e4) {}
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
	local maxDist = ("RescueMaxDistance" in GxLdBot.Settings)
		? GxLdBot.Settings.RescueMaxDistance : 2200.0;
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
		// A human victim is worth crossing more of the map for than a bot victim
		// (the whole point is "my friend got grabbed, someone come get me"). We bias
		// the rescuer-selection score for a human so a slightly-further bot will
		// still commit, but keep a hard distance cap either way so nobody sprints
		// across the level into a fresh pin and gets picked off alone.
		local victimIsHuman = !GxLdBot.IsBot(victim);
		local best = null;
		local bestScore = 999999.0;
		GxLdBot.ForEachSurvivorBot(function(b) {
			if (b == victim || !GxLdBot.IsAlive(b) || GxLdBot.IsUncommandable(b)) {
				return;
			}
			if (GxLdBot.OwnsHighPriorityClaim(b, key)) {
				return;
			}
			local dist = GxLdBot.DistanceBetween(b, victim);
			if (dist > maxDist) {
				return; // too far to reach safely — leave it to whoever's closer
			}
			local profile = GxLdBot.GetProfile(b);
			local bias = (profile != null) ? profile.rescueBias : 80;
			local score = dist - bias * 2.0;
			if (victimIsHuman) {
				score -= 400.0; // human victims win ties / pull a slightly-further rescuer
			}
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
	try { botOrigin = bot.GetOrigin(); } catch (e) { return null; }
	local frame = GxLdBot.GetSituation();
	if (!("threatBySurvivor" in frame)) { return null; }
	local best = { ent = null, score = 999999.0 };
	foreach (sidx, record in frame.threatBySurvivor) {
		if ((GxLdBot.Now() - record.updatedAt) > GxLdBot.Settings.ThreatRecordMaxAge) { continue; }
		try { if ((botOrigin - record.origin).Length() > assistMax) { continue; } } catch (ed) { continue; }
		local picked = GxLdBot.ThreatListTarget(record.specials, assistRadius, 1);
		local bonus = 160.0;
		if (picked == null) {
			picked = GxLdBot.ThreatListTarget(record.commons, assistRadius, assistCount);
			bonus = (picked != null) ? picked.count * 18.0 : 0.0;
		}
		if (picked == null || !GxLdBot.IsValidEntity(picked.ent)) { continue; }
		local score = 999999.0;
		try { score = (botOrigin - picked.ent.GetOrigin()).Length() - bonus; } catch (es) {}
		if (score < best.score) { best.ent = picked.ent; best.score = score; }
	}

	return best.ent;
}

// Is THIS bot itself under close attack (commons swarming it / a special right on
// it, same floor)? Used to split "assist" into two cases: helping a DISTANT
// teammate clear trash is a low-priority pressure action that yields while the
// human is moving (so the bot travels with the player instead of farming), but a
// bot defending ITSELF from a swarm must always be allowed to fight back — that
// suppression was why a trailing bot got surrounded and "couldn't shoot back".
function GxLdBot::AssistIsSelfDefense(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	local radius = GxLdBot.Settings.AssistCommonRadius;
	if (radius > 260.0) {
		radius = 260.0; // self-defense = genuinely close, not map-wide
	}
	local record = GxLdBot.ThreatRecordFor(bot);
	if (record == null) { return false; }
	if (GxLdBot.ThreatListTarget(record.specials, radius, 1) != null) { return true; }
	return GxLdBot.ThreatListTarget(record.commons, radius,
		GxLdBot.Settings.AssistSelfDefenseCount) != null;
}

function GxLdBot::SelfDefenseTargetFor(bot) {
	local record = GxLdBot.ThreatRecordFor(bot);
	if (record == null) { return null; }
	local radius = GxLdBot.Settings.AssistCommonRadius;
	if (radius > 260.0) { radius = 260.0; }
	local picked = GxLdBot.ThreatListTarget(record.specials, radius, 1);
	if (picked == null) {
		picked = GxLdBot.ThreatListTarget(record.commons, radius,
			GxLdBot.Settings.AssistSelfDefenseCount);
	}
	return (picked != null) ? picked.ent : null;
}

// At most one bot performs optional team assist. Prefer rear/flex so point and
// relay keep the route readable; every bot may still self-defend independently.
function GxLdBot::AssignTeamAssist(now) {
	local frame = GxLdBot.GetSituation();
	if (!GxLdBot.Settings.EnableAssist || GxLdBot.TeamModel.phase != "COMBAT") {
		GxLdBot.TeamAssistPlan = { owner = -1, target = null, until = 0.0,
			frameSerial = GxLdBot.WorldSerial };
		return;
	}
	if (now < GxLdBot.TeamAssistPlan.until &&
			GxLdBot.IsValidEntity(GxLdBot.TeamAssistPlan.target)) { return; }
	local target = null;
	local bestPressure = -1;
	foreach (sidx, record in frame.threatBySurvivor) {
		if ((now - record.updatedAt) > GxLdBot.Settings.ThreatRecordMaxAge) { continue; }
		local special = GxLdBot.ThreatListTarget(record.specials,
			GxLdBot.Settings.AssistCommonRadius, 1);
		local commons = GxLdBot.ThreatListTarget(record.commons,
			GxLdBot.Settings.AssistCommonRadius, GxLdBot.Settings.AssistCommonCount);
		local pressure = (special != null) ? 1000 : ((commons != null) ? commons.count : 0);
		local candidate = (special != null) ? special : commons;
		if (candidate != null && pressure > bestPressure) {
			bestPressure = pressure;
			target = candidate.ent;
		}
	}
	if (!GxLdBot.IsValidEntity(target)) {
		GxLdBot.TeamAssistPlan = { owner = -1, target = null, until = now + 0.3,
			frameSerial = GxLdBot.WorldSerial };
		return;
	}
	local owner = -1;
	local bestScore = 999999.0;
	GxLdBot.ForEachSurvivorBot(function(candidateBot) {
		if (!GxLdBot.IsAlive(candidateBot) || GxLdBot.IsUncommandable(candidateBot)) { return; }
		local slot = GxLdBot.FormationSlotFor(candidateBot);
		// HARD-EXCLUDE the leaders (point/relay) from optional team-assist. Data showed
		// them spending 2.4x more time shooting trash than leading — they would win the
		// assign whenever they happened to be closest to a common, then stand still
		// clearing it instead of pushing the route ("原地站住打怪不往前"). Leaders keep
		// route duty; trash-clearing is the rear/flex job. Leaders still SELF-DEFEND
		// independently (SelfDefenseTargetFor, score 96) when swarmed at point-blank —
		// that path does not go through this owner assignment.
		if (slot == "point" || slot == "relay") { return; }
		local slotCost = (slot == "rear") ? -420.0 : ((slot == "flex") ? -280.0 : 0.0);
		local score = GxLdBot.DistanceBetween(candidateBot, target) + slotCost;
		if (score < bestScore) { bestScore = score; owner = candidateBot.GetEntityIndex(); }
	});
	GxLdBot.TeamAssistPlan = { owner = owner, target = target,
		until = now + GxLdBot.Settings.TeamAssistPlanSeconds,
		frameSerial = GxLdBot.WorldSerial };
}

function GxLdBot::TeamAssistTargetFor(bot, now) {
	if (!GxLdBot.IsValidEntity(bot) || now >= GxLdBot.TeamAssistPlan.until ||
			GxLdBot.TeamAssistPlan.owner != bot.GetEntityIndex() ||
			!GxLdBot.IsValidEntity(GxLdBot.TeamAssistPlan.target)) { return null; }
	return GxLdBot.TeamAssistPlan.target;
}

function GxLdBot::EmergencyDefendIntentFor(bot) {
	if (!GxLdBot.IsValidEntity(bot) || !("HumanEmergencyVictim" in GxLdBot)) {
		return null;
	}
	local victim = GxLdBot.HumanEmergencyVictim();
	if (victim == null || !GxLdBot.IsAlive(victim)) {
		return null;
	}
	// Perception delay (DESIGN 3, layer 2): a bot reacts to the emergency only once
	// it has "noticed" — a per-bot, personality-scaled stagger (0.1..0.5s) off the
	// emergency onset. This stops all bots snapping to the victim on the same tick
	// (the tell-tale swarm-mind look); a jumpy bot turns fast, a calm one a beat
	// later. Kept small so it reads as human hesitation, not negligence.
	if (("PerceivesEmergency" in GxLdBot) && !GxLdBot.PerceivesEmergency(bot)) {
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
	if (("BotAllowsProgress" in GxLdBot) && !GxLdBot.BotAllowsProgress(bot)) {
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

	// Formation-specific leash. Point/relay get enough room to hold their slots,
	// but never the old centroid-derived 900u blanket permission. Until reverse
	// path probing lands, their hard limits are the conservative support envelope.
	local formationSlot = ("FormationSlotFor" in GxLdBot)
		? GxLdBot.FormationSlotFor(bot) : "none";
	if (formationSlot == "point") {
		threshold = GxLdBot.Settings.UnprovenForwardMaxDistance;
		local pointDistance = GxLdBot.DistanceBetween(bot, human);
		if (pointDistance > threshold &&
				pointDistance <= GxLdBot.Settings.ReversePathMaxLeadDistance &&
				("CurrentPositionReversePathSafe" in GxLdBot)) {
			// THREE-STATE reverse path (fixes the periodic far-point retract regression):
			//   true  → proven reachable, widen the leash to the far cap.
			//   null  → NOT checked this tick (no heavy budget). Do NOT retract merely
			//           because we couldn't afford the query — widen the leash too, so a
			//           budget-starved tick never yanks a legitimately-far point home.
			//   false → proven UNREACHABLE. Keep the tight UnprovenForwardMaxDistance
			//           threshold so escort pulls this genuinely-stranded point back.
			local reach = GxLdBot.CurrentPositionReversePathSafe(bot, human);
			if (reach != false) {
				threshold = GxLdBot.Settings.ReversePathMaxLeadDistance;
			}
		}
	} else if (formationSlot == "relay") {
		threshold = GxLdBot.Settings.SupportLinkDistance;
	}

	local pos = null;
	try { pos = human.GetOrigin(); } catch (e) { return null; }

	// 回身 trigger A: too far from the human.
	if (GxLdBot.DistanceBetween(bot, human) > threshold) {
		return { pos = pos, human = human };
	}

	// 回身 trigger B: permission comes from the human-connected support graph,
	// never from centroid. If this bot no longer links to that component, escort
	// takes over immediately and pulls it home.
	if (("TargetHasHumanSupport" in GxLdBot)) {
		local currentFlow = null;
		try { currentFlow = GxLdBot.GetFlowFor(bot.GetOrigin()); } catch (ef) {}
		if (!GxLdBot.TargetHasHumanSupport(bot, bot.GetOrigin(), currentFlow)) {
			return { pos = pos, human = human };
		}
	}

	return null;
}

function GxLdBot::CheckBackIntentFor(bot, idx, now) {
	if (!(idx in GxLdBot.CheckBack) || !GxLdBot.IsValidEntity(bot)) {
		return null;
	}
	local state = GxLdBot.CheckBack[idx];
	local human = GxLdBot.NearestHuman(bot);
	if (human == null || !GxLdBot.IsAlive(human) || now >= state.until) {
		delete GxLdBot.CheckBack[idx];
		GxLdBot.SetTableSlot(GxLdBot.GuideCooldownUntil, idx,
			now + GxLdBot.Settings.GuideCheckBackCooldown);
		return null;
	}
	if (GxLdBot.DistanceBetween(bot, human) <= GxLdBot.Settings.GuideCheckBackStopDistance) {
		delete GxLdBot.CheckBack[idx];
		GxLdBot.SetTableSlot(GxLdBot.GuideCooldownUntil, idx,
			now + GxLdBot.Settings.GuideCheckBackCooldown);
		return null;
	}
	local pos = null;
	try { pos = human.GetOrigin(); } catch (e) { return null; }
	return { kind = "checkback", pos = pos, human = human };
}

function GxLdBot::IdleWanderPos(bot, human) {
	if (!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(human)) {
		return null;
	}
	local origin = null;
	try { origin = human.GetOrigin(); } catch (e) { return null; }
	local idx = 0;
	try { idx = bot.GetEntityIndex(); } catch (e2) {}
	// Stable idle station. The old time-varying angle changed destination every
	// three seconds and made bots orbit/backtrack around the player.
	local angle = idx * 1.71;
	local radius = GxLdBot.Settings.IdleWanderRadius * (0.55 + ((idx % 3) * 0.18));
	return Vector(
		origin.x + cos(angle) * radius,
		origin.y + sin(angle) * radius,
		origin.z
	);
}

function GxLdBot::NormalizeProgressIntent(pres) {
	if (pres == null) { return null; }
	if (typeof pres == "table" && ("guide" in pres)) {
		return { kind = "guide", human = pres.human };
	}
	if (typeof pres == "table" && ("relayHold" in pres)) {
		return { kind = "relay_hold", human = pres.human };
	}
	if (typeof pres == "table" && ("pos" in pres) && pres.pos != null) {
		local moveKind = (("intentKind" in pres) && pres.intentKind == "relay")
			? "relay" : "progress";
		return { kind = moveKind, pos = pres.pos, area = ("area" in pres) ? pres.area : null };
	}
	return { kind = "progress", pos = pres };
}

// Survival actions remain hard-priority. Team/expression actions compete by
// utility with a short continuity bonus so threshold edges do not ping-pong.
function GxLdBot::SelectUtilityIntent(bot, idx, now) {
	local candidates = [];
	local add = function(intent, score, minHold) {
		if (intent == null) { return; }
		GxLdBot.SetTableSlot(intent, "score", score);
		GxLdBot.SetTableSlot(intent, "minHold", minHold);
		GxLdBot.SetTableSlot(intent, "lane", intent.kind == "expression" ? "EXPRESSION" : "TEAM");
		if (!("reason" in intent)) { GxLdBot.SetTableSlot(intent, "reason", intent.kind); }
		if (idx in GxLdBot.Action) {
			local active = GxLdBot.Action[idx];
			if (active.kind == intent.kind && ("minHoldUntil" in active) && now < active.minHoldUntil) {
				intent.score += 35.0;
			}
		}
		candidates.append(intent);
	};

	local escort = GxLdBot.EscortIntentFor(bot);
	if (escort != null) { add({ kind = "escort", pos = escort.pos, human = escort.human }, 100.0, 0.7); }

	if (GxLdBot.Settings.EnableAssist) {
		local selfDefenseTarget = GxLdBot.SelfDefenseTargetFor(bot);
		local selfDefense = selfDefenseTarget != null;
		local plannedTarget = GxLdBot.TeamAssistTargetFor(bot, now);
		if (idx in GxLdBot.Action && GxLdBot.Action[idx].kind == "assist") {
			local activeAssist = GxLdBot.Action[idx];
			if (now < activeAssist.until && "target" in activeAssist &&
					GxLdBot.IsValidEntity(activeAssist.target) &&
					(selfDefense || plannedTarget == activeAssist.target)) {
				add({ kind = "assist", target = activeAssist.target },
					selfDefense ? 96.0 : 66.0, 0.35);
			}
		}
		local yieldWhenMoving = (!("AssistYieldWhenMoving" in GxLdBot.Settings)) ||
			GxLdBot.Settings.AssistYieldWhenMoving;
		local humanMoving = yieldWhenMoving && GxLdBot.HumanIsMoving();
		if (selfDefense) {
			add({ kind = "assist", target = selfDefenseTarget, reason = "self_defense" }, 96.0, 0.4);
		} else if (!humanMoving && plannedTarget != null &&
				("BotAllowsAssist" in GxLdBot) && GxLdBot.BotAllowsAssist(bot)) {
			add({ kind = "assist", target = plannedTarget, reason = "team_assist_owner" }, 66.0, 0.35);
		}
	}

	local checkBack = GxLdBot.CheckBackIntentFor(bot, idx, now);
	if (checkBack != null) { add(checkBack, 86.0, 1.1); }

	local progress = null;
	if ("ProgressIntentFor" in GxLdBot) {
		progress = GxLdBot.NormalizeProgressIntent(GxLdBot.ProgressIntentFor(bot));
		if (progress != null) {
			local slot = ("FormationSlotFor" in GxLdBot) ? GxLdBot.FormationSlotFor(bot) : "none";
			local score = (slot == "point") ? 78.0 : 69.0;
			if (progress.kind == "guide") { score += 3.0; }
			add(progress, score, (progress.kind == "guide") ? 1.0 : 0.65);
		}
	}
	if (progress == null && (!("HasAliveHuman" in GxLdBot) || !GxLdBot.HasAliveHuman())) {
		local scoutPos = GxLdBot.ScoutIntentFor(bot);
		if (scoutPos != null) { add({ kind = "scout", pos = scoutPos }, 62.0, 0.6); }
	}

	if ("ExpressionIntentFor" in GxLdBot) {
		add(GxLdBot.ExpressionIntentFor(bot), 34.0, 0.8);
	}
	local human = GxLdBot.IdleIntentFor(bot);
	if (human != null) { add({ kind = "idle", human = human }, 18.0, 0.7); }

	local best = null;
	foreach (i, candidate in candidates) {
		if (best == null || candidate.score > best.score) { best = candidate; }
	}
	return best;
}

// ---- intent selection -------------------------------------------------------

function GxLdBot::ComputeIntent(bot, idx, now) {
	// 1) rescue
	if (GxLdBot.Settings.EnableRescue) {
		local r = GxLdBot.RescueVictimFor(bot);
		if (r != null) {
			return { kind = "rescue", info = r, lane = "SURVIVAL", score = 1000.0,
				minHold = 0.0, reason = "rescue_claim" };
		}
	}

	// 2) emergency defend: if a human is pinned/incapped, immediately attack the
	// threat near them (Witch / special / close commons) instead of watching.
	local defend = GxLdBot.EmergencyDefendIntentFor(bot);
	if (defend != null) {
		return { kind = "defend", info = defend, lane = "SURVIVAL", score = 980.0,
			minHold = 0.0, reason = "perceived_emergency" };
	}

	// 3) retreat — continue an active burst, else maybe start a new one
	if (GxLdBot.Settings.EnableRetreat) {
		if (idx in GxLdBot.Action && GxLdBot.Action[idx].kind == "retreat") {
			if (now < GxLdBot.Action[idx].until) {
				local t = GxLdBot.NearestThreatNear(bot,
					GxLdBot.Settings.RetreatCommonRadius, GxLdBot.Settings.RetreatCommonRadius * 2.0);
				if (t != null) {
					return { kind = "retreat", threat = t, lane = "SURVIVAL", score = 940.0,
						minHold = 0.15, reason = "retreat_continue" };
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
				return { kind = "retreat", threat = t2, lane = "SURVIVAL", score = 940.0,
					minHold = 0.15, reason = "close_pressure" };
			}
		}
	}

	// 4) cover
	if (GxLdBot.Settings.EnableCover) {
		local v = GxLdBot.CoverVictimFor(bot);
		if (v != null) {
			return { kind = "cover", victim = v, lane = "SURVIVAL", score = 900.0,
				minHold = 0.35, reason = "cover_claim" };
		}
	}

	// 5) heal self: start only when safe, then commit long enough to finish.
	if (GxLdBot.Settings.EnableHeal && GxLdBot.HealShouldContinue(bot, idx, now)) {
		return { kind = "heal", lane = "SURVIVAL", score = 860.0,
			minHold = 0.5, reason = "heal_continue" };
	}
	if (GxLdBot.Settings.EnableHeal && GxLdBot.HealIntentFor(bot)) {
		return { kind = "heal", lane = "SURVIVAL", score = 860.0,
			minHold = 0.5, reason = "heal_safe" };
	}

	// 6) frequent close-threat shove (right click) before optional movement.
	local shoveTarget = GxLdBot.CombatShoveTargetFor(bot, idx, now);
	if (shoveTarget != null) {
		return { kind = "shove", target = shoveTarget, lane = "SURVIVAL", score = 820.0,
			minHold = 0.2, reason = "close_threat" };
	}

	return GxLdBot.SelectUtilityIntent(bot, idx, now);
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
		if (far || (now - a.movedAt) > GxLdBot.Settings.MoveCommandRefresh) {
			reissue = true;
		}
	}
	if (reissue) {
		if (!GxLdBot.BotMoveTo(bot, pos)) {
			GxLdBot.EndAction(bot, idx, true);
			return null;
		}
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
		if (!GxLdBot.BotAttackTarget(bot, info.target)) { GxLdBot.EndAction(bot, idx, true); }
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
			GxLdBot.LeaseForcedBit(bot, GxLdBot.BTN_USE);
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
			// Global shove floor (DESIGN/user: "5s between shoves"). The old micro
			// cooldown (0.38) let a bot re-shove almost every tick, which read as
			// spammy air-shoving next to a Tank. We take the LARGER of the micro gap
			// and the global floor. NOTE: this only gates COMBAT shove — rescue shove
			// (breaking a pin off a teammate) is deliberately exempt and never reads
			// ShoveCooldownUntil, so a rescue can still shove repeatedly to free you.
			local micro = GxLdBot.Settings.CombatShoveCooldown;
			local floor = ("ShoveGlobalCooldown" in GxLdBot.Settings)
				? GxLdBot.Settings.ShoveGlobalCooldown : micro;
			local gap = (micro > floor) ? micro : floor;
			GxLdBot.SetTableSlot(GxLdBot.ShoveCooldownUntil, idx, now + duration + gap);
		}
		a.target = intent.target;
		GxLdBot.ClearHeal(bot);
		if (!GxLdBot.SetShove(bot, intent.target)) { GxLdBot.EndAction(bot, idx, true); }
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
			if (!GxLdBot.SetShove(bot, info.special)) { GxLdBot.EndAction(bot, idx, true); }
		} else {
			GxLdBot.ClearShove(bot);
			if (!GxLdBot.BotAttackTarget(bot, info.special)) { GxLdBot.EndAction(bot, idx, true); }
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
		if (!GxLdBot.BotRetreatFrom(bot, intent.threat)) { GxLdBot.EndAction(bot, idx, true); }
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
		if (!GxLdBot.BotAttackTarget(bot, intent.target)) { GxLdBot.EndAction(bot, idx, true); }
		return;
	}

	// Guide-hold (player's "walk to a mid distance, then turn and look back at me
	// to signal the way" — instead of creeping close and shuffling back and forth).
	// The scout has reached its lead point; it stops (hand back to vanilla so it
	// stands its ground) and faces the human. It is NOT moved anywhere, so escort
	// can't yank it home and re-trigger the shuffle. When the human catches up their
	// flow rises, the scout's target flow rises with it, and progress moves it
	// forward again on the next tick — a natural "breadcrumb waits, then leads on".
	if (intent.kind == "guide") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "guide") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			// Record the hold spot = where the scout arrived. We PIN it here by
			// commanding move-to-self, NOT BotResetCommand — reset hands control to
			// vanilla, which then walks the (ahead-of-team) bot back toward the human,
			// dropping its flow so it re-triggers progress and creeps forward again:
			// that back-and-forth is the "左右来回走" the player saw. Pinning stops it.
			local holdPos = null;
			try { holdPos = bot.GetOrigin(); } catch (e) {}
			a = { kind = "guide", since = now, until = 0.0, ready = 0.0,
				target = intent.human, pos = holdPos, basePos = holdPos, fidgetAt = now,
				nextGazeAt = now, movedAt = now, holding = true, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			// PIN NOW (the fix the comment above always described but never did): the
			// prior action was ended with reset, so without an immediate move-to-self
			// vanilla owns the bot until the drift check below first fires (>80u), and
			// in those seconds it walks the ahead-of-team bot back toward the human —
			// the exact lead-shrink / back-and-forth this block exists to prevent. One
			// move-to-hold on creation claims the spot right away. If that command
			// FAILS (CanControlBots false / CommandABot missing), don't leave a dead
			// guide action that never retries (creation drift is 0) — end it and let
			// vanilla have the bot this tick.
			if (holdPos == null || !GxLdBot.BotMoveTo(bot, holdPos)) {
				GxLdBot.EndAction(bot, idx, true);
				return;
			}
			GxLdBot.Notify("action:guide:" + idx,
				GxLdBot.SafeName(bot) + " leading the way", 12.0);
		}
		a.target = intent.human;
		GxLdBot.ClearShove(bot);
		// Keep the scout pinned at its hold spot. Re-command move-to-hold ONLY when it
		// has actually drifted off (vanilla nudge / knockback) or periodically, NOT
		// every tick — re-issuing a move order every 0.18s to the spot it's already on
		// makes it micro-path and jitter (that's the "左右来回走" the player reported).
		// Living micro-movement: every FidgetInterval-ish seconds shift the hold
		// spot a small bounded step off the ORIGINAL arrival point (basePos), so a
		// waiting scout repositions like a real player instead of freezing. Bounded
		// by FidgetRadius so it never drifts off station.
		if ("basePos" in a && a.basePos != null
				&& ("FidgetEnable" in GxLdBot.Settings) && GxLdBot.Settings.FidgetEnable
				&& now >= a.fidgetAt) {
			a.fidgetAt = now + GxLdBot.RandFloat(GxLdBot.Settings.FidgetInterval * 0.6,
				GxLdBot.Settings.FidgetInterval * 1.4);
			local r = GxLdBot.Settings.FidgetRadius;
			local ang = GxLdBot.RandFloat(0.0, 6.283);
			local dist = GxLdBot.RandFloat(r * 0.35, r);
			local cand = Vector(a.basePos.x + cos(ang) * dist, a.basePos.y + sin(ang) * dist,
				a.basePos.z);
			// NAV VALIDATION (垂直图防摔): the raw random point can land in a wall,
			// off-mesh, or over a one-way drop near railings/ledges. Only adopt it if
			// a nav area sits under it on the same floor; otherwise keep the current
			// hold spot (skip this fidget) so we never command the point off a cliff.
			if (!("FidgetPointSafe" in GxLdBot) || GxLdBot.FidgetPointSafe(cand, a.basePos.z)) {
				a.pos = cand;
			}
		}
		if (a.pos != null) {
			local drift = 0.0;
			try { drift = (bot.GetOrigin() - a.pos).Length(); } catch (e2) {}
			if (drift > 80.0 || (drift > 30.0 && (now - a.movedAt) > 4.0)) {
				if (!GxLdBot.BotMoveTo(bot, a.pos)) {
					GxLdBot.EndAction(bot, idx, true);
					return;
				}
				a.movedAt = now;
			}
		}
		if (!("nextGazeAt" in a)) {
			GxLdBot.SetTableSlot(a, "nextGazeAt", now);
		}
		local gazeSafe = !("GuideGazeOnlySafe" in GxLdBot.Settings) ||
			!GxLdBot.Settings.GuideGazeOnlySafe ||
			(("TeamModel" in GxLdBot) && GxLdBot.TeamModel.phase == "SAFE");
		if (gazeSafe && GxLdBot.IsValidEntity(intent.human) && now >= a.nextGazeAt) {
			// A visible look-back pulse, not continuous 0.18s aim authoring. Expression
			// antics are intentionally removed from guide until the later scheduler can
			// budget and stagger them safely.
			GxLdBot.FaceEntity(bot, intent.human);
			a.nextGazeAt = now + GxLdBot.RandFloat(
				GxLdBot.Settings.GuideGazePulseMin, GxLdBot.Settings.GuideGazePulseMax);
		}
		// NOTE: the old CHECK_BACK state machine used to make a parked point PHYSICALLY
		// walk back to the human after GuideCheckBackDelay, then sit on a 10s cooldown
		// before it could lead again. In play that read as "weird": you stop to fight /
		// loot, the breadcrumb suddenly turns around and comes back, and when you move
		// on there's nobody out front for 10s. A leading buddy who is genuinely ahead
		// should HOLD the forward spot and keep glancing back (the pulse-gaze above) —
		// not abandon the lead. When you catch up / pass the bot, humanFlow >= botFlow
		// and progress re-pushes it forward on its own. So: no physical walk-back.
		return;
	}

	// Relay hold: keep the bridge bot at its midpoint without copying the point's
	// look-back performance. It only holds formation; attention remains vanilla.
	if (intent.kind == "relay_hold") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "relay_hold") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			local holdPos = null;
			try { holdPos = bot.GetOrigin(); } catch (e) {}
			a = { kind = "relay_hold", since = now, until = 0.0, ready = 0.0,
				target = intent.human, pos = holdPos, movedAt = now,
				holding = true, claimKey = null };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			// PIN the relay at its arrival spot on creation (same as guide): the
			// EndAction(...,true) above handed control to vanilla, which would walk the
			// bot back toward the human before the drift re-command below ever fires.
			// A move-to-self holds the formation slot from tick one. If holdPos is
			// null (GetOrigin threw) OR the command fails (no lease / CanControlBots
			// false), don't leave a dead relay_hold action with pos=null that will
			// NEVER retry (a.pos != null never holds, so the drift re-command below is
			// unreachable) and never self-heal — end it and let the arbiter re-plan
			// next tick. Written identically to the guide block so the two can't drift.
			if (holdPos == null || !GxLdBot.BotMoveTo(bot, holdPos)) {
				GxLdBot.EndAction(bot, idx, true);
				return;
			}
		}
		GxLdBot.ClearShove(bot);
		GxLdBot.ClearGoof(bot);
		if (a.pos != null) {
			local drift = 0.0;
			try { drift = (bot.GetOrigin() - a.pos).Length(); } catch (e2) {}
			if (drift > 80.0 || (drift > 30.0 && (now - a.movedAt) > 4.0)) {
				if (!GxLdBot.BotMoveTo(bot, a.pos)) {
					GxLdBot.EndAction(bot, idx, true);
					return;
				}
				a.movedAt = now;
			}
		}
		return;
	}

	if (intent.kind == "progress") {
		GxLdBot.IssueMoveIntent(bot, idx, "progress", intent.pos, null, now);
		return;
	}

	if (intent.kind == "relay") {
		GxLdBot.IssueMoveIntent(bot, idx, "relay", intent.pos, null, now);
		return;
	}

	if (intent.kind == "checkback") {
		GxLdBot.IssueMoveIntent(bot, idx, "checkback", intent.pos, intent.human, now);
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

	if (intent.kind == "expression") {
		local a = (idx in GxLdBot.Action) ? GxLdBot.Action[idx] : null;
		if (a != null && a.kind != "expression") {
			GxLdBot.EndAction(bot, idx, true);
			a = null;
		}
		if (a == null) {
			a = { kind = "expression", since = now, until = intent.until, ready = 0.0,
				target = intent.human, pos = intent.pos, movedAt = 0.0, holding = true,
				claimKey = null, expressionKind = intent.expressionKind,
				lastToggle = 0.0, ducked = false, gazeDone = false };
			GxLdBot.SetTableSlot(GxLdBot.Action, idx, a);
			// Expression owns no movement. Ending the previous action/resetting first is
			// what makes a crouch/check-in visibly stationary.
		}
		a.until = intent.until;
		a.target = intent.human;
		a.pos = intent.pos;
		GxLdBot.ClearShove(bot);
		GxLdBot.ClearHeal(bot);
		if (a.expressionKind == "attention") {
			if (!a.gazeDone && a.pos != null) {
				if (!GxLdBot.FacePosition(bot, a.pos)) { GxLdBot.EndAction(bot, idx, true); return; }
				a.gazeDone = true;
			}
		} else if (a.expressionKind == "checkin") {
			if (!a.gazeDone && GxLdBot.IsValidEntity(a.target)) {
				if (!GxLdBot.FaceEntity(bot, a.target)) { GxLdBot.EndAction(bot, idx, true); return; }
				a.gazeDone = true;
			}
		} else if (a.expressionKind == "goof") {
			if (!a.gazeDone && GxLdBot.IsValidEntity(a.target)) {
				GxLdBot.FaceEntity(bot, a.target);
				a.gazeDone = true;
			}
			if ((now - a.lastToggle) >= GxLdBot.Settings.GoofCrouchToggle) {
				a.lastToggle = now;
				try {
					local bits = NetProps.GetPropInt(bot, "m_afButtonForced");
					a.ducked = ((bits & GxLdBot.BTN_DUCK) == 0);
					NetProps.SetPropInt(bot, "m_afButtonForced",
						a.ducked ? (bits | GxLdBot.BTN_DUCK) : (bits & ~GxLdBot.BTN_DUCK));
					if (a.ducked) { GxLdBot.LeaseForcedBit(bot, GxLdBot.BTN_DUCK); }
					else { GxLdBot.ReleaseForcedBit(bot, GxLdBot.BTN_DUCK); }
				} catch (e) {}
			}
		}
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
		GxLdBot.IdleSpeak(bot, human); // logs only; idle does not force voice lines
		return;
	}
}

// Drop a bot's action: release any claim it owned, clear a stuck shove, and
// (on a real state transition) reset it to vanilla so no stale command lingers.
function GxLdBot::EndAction(bot, idx, doReset) {
	if (idx in GxLdBot.Action) {
		local a = GxLdBot.Action[idx];
		if (a.kind == "expression" && "ExpressionPlan" in GxLdBot && idx in GxLdBot.ExpressionPlan) {
			delete GxLdBot.ExpressionPlan[idx];
		}
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
	GxLdBot.ClearGoof(bot);
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
		GxLdBot.ClearGoof(b);
	});
}

// Unified actuator cleanup. This is intentionally safe to call while Sleeping:
// new enactment is blocked, but reset/bit release must still be allowed so the
// script can hand every bot back to vanilla during multiplayer sleep, takeover,
// round transitions, or module shutdown.
function GxLdBot::QuiesceBot(bot, reason = "quiesce", doReset = true) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return;
	}
	local idx = bot.GetEntityIndex();
	GxLdBot.ReleaseMovementBoost(bot, reason);
	if (idx in GxLdBot.Action) {
		GxLdBot.EndAction(bot, idx, doReset);
	} else {
		GxLdBot.ClearShove(bot);
		GxLdBot.ClearHeal(bot);
		GxLdBot.ClearGoof(bot);
		local ownsCommand = false;
		if (idx in GxLdBot.ActuatorLease) {
			ownsCommand = GxLdBot.ActuatorLease[idx].commandOwned;
		}
		if (doReset && ownsCommand) {
			GxLdBot.BotResetCommand(bot);
		}
	}
	if (idx in GxLdBot.ActuatorLease) {
		delete GxLdBot.ActuatorLease[idx];
	}
	GxLdBot.Log("quiesce " + GxLdBot.SafeName(bot) + " reason=" + reason);
}

function GxLdBot::QuiesceAll(reason = "quiesce_all") {
	GxLdBot.ForEachSurvivorBot(function(bot) {
		GxLdBot.QuiesceBot(bot, reason, true);
	});
	// Covers takeover/team-swap entities that are no longer returned as bots but
	// still carry a lease indexed from the previous frame.
	GxLdBot.ReleaseAllMovementBoosts(reason);
	GxLdBot.Action = {};
	GxLdBot.ActuatorLease = {};
	GxLdBot.Claims = {};
	GxLdBot.CheckBack = {};
	GxLdBot.GuideCooldownUntil = {};
	GxLdBot.ExpressionPlan = {};
	GxLdBot.ExpressionPlanTime = -999.0;
	GxLdBot.SpeechQueue = [];
	GxLdBot.TeamAssistPlan = { owner = -1, target = null, until = 0.0, frameSerial = -1 };
}

// ---- the arbiter tick -------------------------------------------------------

function GxLdBot::ActionArbiterTick() {
	if (GxLdBot.Sleeping || GxLdBot.UpdateSleepState()) {
		return;
	}
	if (!GxLdBot.Settings.EnableActions) {
		if (!GxLdBot.ActionDisabledCleaned) {
			GxLdBot.QuiesceAll("actions_disabled");
			GxLdBot.ActionDisabledCleaned = true;
			GxLdBot.Log("actions disabled: reset all bot commands", true);
		}
		return;
	}
	GxLdBot.ActionDisabledCleaned = false;
	local now = GxLdBot.Now();
	// Per-tick heavy-work budget is now a COUNTER, not a single boolean. The old
	// single-slot flag let only ONE bot run a nav expansion per tick, so point and
	// relay had to alternate — one advanced while the other held, producing the
	// "走一步停一步" step-stop the player reported. A small count (HeavySliceMax)
	// lets BOTH leaders expand nav on the same tick while still capping total heavy
	// ops per tick so we never return to the unbounded PERF spikes. The infected
	// sampler, when it does a scan, consumes one slot.
	GxLdBot.HeavySliceCount = (("UpdateThreatSampler" in GxLdBot)
		&& GxLdBot.UpdateThreatSampler()) ? 1 : 0;

	GxLdBot.AssignRescues(now);
	GxLdBot.AssignCover(now);
	GxLdBot.AssignTeamAssist(now);

	// Compute the point's read-only decision first. This gives the lead bot first
	// refusal on the single heavy nav-expansion slice even when entity iteration
	// happens to visit the relay first. If point reuses cache/holds, the slice stays
	// free and the relay may consume it later in the same arbiter tick.
	local precomputedPointIdx = -1;
	local precomputedPointIntent = null;
	local heavyMax = ("HeavySliceMax" in GxLdBot.Settings) ? GxLdBot.Settings.HeavySliceMax : 3;
	if (GxLdBot.HeavySliceCount < heavyMax && ("FormationEntityFor" in GxLdBot)) {
		local pointBot = GxLdBot.FormationEntityFor("point");
		if (pointBot != null && GxLdBot.IsValidEntity(pointBot) && GxLdBot.IsAlive(pointBot) &&
				!GxLdBot.IsUncommandable(pointBot)) {
			precomputedPointIdx = pointBot.GetEntityIndex();
			precomputedPointIntent = GxLdBot.ComputeIntent(pointBot, precomputedPointIdx, now);
		}
	}

	GxLdBot.ForEachSurvivorBot(function(bot) {
		local idx = bot.GetEntityIndex();

		if (!GxLdBot.IsAlive(bot)) {
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, false); // can't command a dead bot, just release state
			}
			return;
		}

		if (GxLdBot.IsUncommandable(bot)) {
			// LADDER FIX (the "climbs to the middle then falls / gets stuck" bug):
			// EndAction's reset issues BotResetCommand (cmd=3), which INTERRUPTS the
			// engine's in-progress ladder traversal and drops the bot off partway up.
			// While on a ladder (movetype 9) release our action state WITHOUT the reset
			// so vanilla finishes the climb uninterrupted. ClearShove/Heal/Goof only
			// drop forced button bits and don't affect the climb, so they stay.
			local onLadder = false;
			try { onLadder = (NetProps.GetPropInt(bot, "movetype") == 9); } catch (el) {}
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, !onLadder);
			} else if (!onLadder) {
				GxLdBot.ClearShove(bot);
			}
			return;
		}

		local intent = (idx == precomputedPointIdx)
			? precomputedPointIntent : GxLdBot.ComputeIntent(bot, idx, now);
		if (intent == null) {
			if (idx in GxLdBot.Action) {
				GxLdBot.EndAction(bot, idx, true); // transition to vanilla — reset ONCE
			} else {
				GxLdBot.ClearShove(bot);
			}
			return;
		}

		GxLdBot.EnactIntent(bot, idx, intent, now);
		if (idx in GxLdBot.Action && ("minHold" in intent)) {
			local holdUntil = now + intent.minHold;
			if (!("minHoldUntil" in GxLdBot.Action[idx]) ||
					GxLdBot.Action[idx].minHoldUntil < holdUntil) {
				GxLdBot.SetTableSlot(GxLdBot.Action[idx], "minHoldUntil", holdUntil);
			}
			GxLdBot.SetTableSlot(GxLdBot.Action[idx], "lane",
				("lane" in intent) ? intent.lane : "TEAM");
			GxLdBot.SetTableSlot(GxLdBot.Action[idx], "score",
				("score" in intent) ? intent.score : 0.0);
			GxLdBot.SetTableSlot(GxLdBot.Action[idx], "reason",
				("reason" in intent) ? intent.reason : intent.kind);
		}
	});
}

function GxLdBot::PrintActions(player) {
	local any = false;
	foreach (idx, a in GxLdBot.Action) {
		any = true;
		local tgt = "-";
		if ("target" in a && a.target != null && GxLdBot.IsValidEntity(a.target)) {
			tgt = GxLdBot.SafeName(a.target);
			if (tgt == "") { try { tgt = a.target.GetClassname(); } catch (e) { tgt = "entity"; } }
		}
		GxLdBot.Chat(player, "idx=" + idx + " action=" + a.kind +
			" lane=" + (("lane" in a) ? a.lane : "-") +
			" score=" + (("score" in a) ? a.score : 0) +
			" target=" + tgt + " for=" + (GxLdBot.Now() - a.since) + "s" +
			" reason=" + (("reason" in a) ? a.reason : "-"));
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
	// Persistent game log sampling: runs on its own interval (GameLogInterval),
	// independent of the arbiter tick, so we get a steady per-bot telemetry stream
	// to review after a play session. Guarded/throttled inside GameLogSample.
	GxLdBot.SafeCall("gamelog", function() {
		if ("GameLogSample" in GxLdBot) { GxLdBot.GameLogSample(); }
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
	GxLdBot.ActuatorLease = {};
	GxLdBot.CheckBack = {};
	GxLdBot.GuideCooldownUntil = {};
	GxLdBot.ExpressionPlan = {};
	GxLdBot.ExpressionPlanTime = -999.0;
	GxLdBot.TeamAssistPlan = { owner = -1, target = null, until = 0.0, frameSerial = -1 };
	GxLdBot.RetreatCooldownUntil = {};
	GxLdBot.ShoveCooldownUntil = {};
	GxLdBot.ActionDisabledCleaned = false;
	GxLdBot.ForEachSurvivorBot(function(b) {
		GxLdBot.ClearShove(b);
		GxLdBot.ClearHeal(b);
		if ("ClearGoof" in GxLdBot) { GxLdBot.ClearGoof(b); }
	});
	GxLdBot.StartArbiterThink();
});
