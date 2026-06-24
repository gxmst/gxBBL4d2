// gxLdBot progress module: flow-based autonomous map advancement.
//
// THE FIX for "bots won't lead / I always have to open the path."
// The old scout aimed at (human_origin + human_eye_forward * 320), so bots
// only drifted toward where the HUMAN was looking and never knew where the map
// exit actually was. This module instead pushes bots along the map's nav FLOW
// (mission start = 0 -> exit = max). "Forward" now means "toward the
// objective," so a bot can confidently walk the route ahead of a stationary
// human instead of waiting to be led.
//
// Strength + human feel: each bot leads by a personality/role-scaled flow
// margin (point pushes far ahead, anchor stays near the human), capped so
// nobody bolts off the map alone. All forward pressure is suppressed under
// threat / pin / horde and when separation from the human is already large
// (escort discipline) — randomize style, not basic survival responsibility.
//
// Enacted by the action arbiter (actions.nut) as the "progress" intent slot, so
// every CommandABot still lives in one place.
//
// Verified APIs (used by the shipped Advanced Bot AI - Custom mod):
//   GetFlowDistanceForPosition(pos)    aiupdatehandler.nut:4168 (global)
//   NavMesh.GetNavAreasInRadius(o,r,t) aiupdatehandler.nut:2420
//   area.GetCenter() / area.IsBlocked  aiupdatehandler.nut:2429-2430

// Flow distance of a world position, or null if this map has no usable flow
// (finales / survival arenas are flat) so auto-progress simply disables there.
function GxLdBot::GetFlowFor(pos) {
	if (pos == null) {
		return null;
	}
	// GetFlowDistanceForPosition is a map-script global. In the director_base
	// scope it is usually visible at the root (the reference mod calls it bare),
	// but fall back to g_MapScript so we still work if it is only scoped there.
	local f = null;
	try {
		if ("GetFlowDistanceForPosition" in getroottable()) {
			f = GetFlowDistanceForPosition(pos);
		} else if ("g_MapScript" in getroottable() &&
				"GetFlowDistanceForPosition" in g_MapScript) {
			f = g_MapScript.GetFlowDistanceForPosition(pos);
		} else {
			return null;
		}
	} catch (e) {
		return null;
	}
	if (f == null) {
		return null;
	}
	try {
		f = f.tofloat();
	} catch (e2) {
		return null;
	}
	if (f < 0.0) {
		return null;
	}
	return f;
}

// Highest flow among alive humans (the furthest-progressed human), or null when
// there are no humans (all-bot game) so bots fall back to leading off their own
// flow and self-complete the map.
function GxLdBot::HumanMaxFlow() {
	local best = null;
	GxLdBot.ForEachSurvivor(function(s) {
		if (GxLdBot.IsBot(s) || !GxLdBot.IsAlive(s)) {
			return;
		}
		local f = null;
		try { f = GxLdBot.GetFlowFor(s.GetOrigin()); } catch (e) {}
		if (f != null && (best == null || f > best)) {
			best = f;
		}
	});
	return best;
}

// How far ahead (in flow units) this bot is allowed to push, from its role's
// lead bias. point/flanker lead a lot; anchor may sit slightly behind.
function GxLdBot::LeadFlowFor(profile) {
	if (profile == null) {
		return 0.0;
	}
	local lead = (profile.leadBias - 50) * GxLdBot.Settings.LeadFlowPerBias;
	if ("cardProgressLeadBonus" in profile) {
		lead += profile.cardProgressLeadBonus;
	}
	if (lead < -150.0) { lead = -150.0; }
	if (lead > GxLdBot.Settings.ProgressMaxLeadFlow) { lead = GxLdBot.Settings.ProgressMaxLeadFlow; }
	return lead;
}

// Search nav areas around the bot and return the center of the one that best
// advances flow toward targetFlow without overshooting the lead cap. Returns a
// Vector or null. Bounded by ProgressMaxAreas so the scan stays cheap.
function GxLdBot::BestForwardArea(bot, botFlow, targetFlow) {
	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return null; }

	local areas = {};
	try {
		NavMesh.GetNavAreasInRadius(origin, GxLdBot.Settings.ProgressScanRadius, areas);
	} catch (e2) {
		return null;
	}

	local best = null;
	local bestScore = -999999.0;
	local checked = 0;
	local minGain = GxLdBot.Settings.ProgressMinAdvanceFlow;

	foreach (area in areas) {
		checked++;
		if (checked > GxLdBot.Settings.ProgressMaxAreas) {
			break;
		}
		if (area == null) {
			continue;
		}
		try {
			if (("IsBlocked" in area) && (area.IsBlocked(2, false) || area.IsBlocked(2, true))) {
				continue;
			}
		} catch (eb) {}

		local spot = null;
		try { spot = area.GetCenter(); } catch (ec) { continue; }
		if (spot == null) {
			continue;
		}

		local f = GxLdBot.GetFlowFor(spot);
		if (f == null) {
			continue;
		}
		if (f <= botFlow + minGain) {
			continue; // not meaningfully forward
		}
		if (f > targetFlow + 60.0) {
			continue; // past our allowed lead — don't bolt straight to the exit
		}

		local dist = 999999.0;
		try { dist = (spot - origin).Length(); } catch (ed) {}
		// Prefer the biggest forward flow gain, lightly penalize walking distance
		// so the bot steps to a nearby forward area rather than the farthest one.
		local score = (f - botFlow) - (dist * 0.08);
		if (score > bestScore) {
			bestScore = score;
			best = spot;
		}
	}
	return best;
}

// Decision only: the world position this bot should advance toward to push the
// map forward, or null to leave it to vanilla (follow / fight). The arbiter
// enacts the move under the "progress" intent slot. Throttled per bot so the flow
// scan runs ~ProgressInterval, not every 0.18s arbiter tick. Reuses LastScout /
// LastScoutTarget state, which is already cleared on round start + stale-bot
// cleanup.
function GxLdBot::ProgressIntentFor(bot) {
	if (!GxLdBot.Settings.EnableScout || !GxLdBot.Settings.EnableProgress) {
		return null;
	}
	if (!GxLdBot.IsValidEntity(bot)) {
		return null;
	}
	local hasHuman = ("HasAliveHuman" in GxLdBot) && GxLdBot.HasAliveHuman();
	if (hasHuman && !GxLdBot.TeamHasLeftSafeArea()) {
		return null; // don't bolt the start saferoom before the human moves
	}
	if (("TeamUnderStress" in GxLdBot) && GxLdBot.TeamUnderStress()) {
		return null; // someone pinned — hold, don't wander off
	}

	local profile = GxLdBot.GetProfile(bot);
	if (profile == null) {
		return null;
	}
	if (hasHuman && GxLdBot.BotInStartArea(bot)) {
		return null;
	}

	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return null; }

	local botFlow = GxLdBot.GetFlowFor(origin);
	if (botFlow == null) {
		return null; // no flow on this map (finale/survival) — no auto-progress
	}

	local human = GxLdBot.NearestHuman(bot);
	local humanFlow = GxLdBot.HumanMaxFlow();
	local baseFlow = (humanFlow != null) ? humanFlow : botFlow;
	local targetFlow = baseFlow + GxLdBot.LeadFlowFor(profile);
	local now = GxLdBot.Now();
	if (hasHuman && (now - GxLdBot.LastTeamMoveTime) >= GxLdBot.Settings.ActiveAdvanceDelay) {
		targetFlow += GxLdBot.Settings.ActiveAdvanceFlowBoost;
		local maxTarget = baseFlow + GxLdBot.Settings.ProgressMaxLeadFlow;
		if (targetFlow > maxTarget) {
			targetFlow = maxTarget;
		}
	}

	// Already at/past our allowed lead: hold and let vanilla escort pull us back
	// toward the team instead of pushing further forward.
	if (botFlow >= targetFlow - GxLdBot.Settings.ProgressFlowTolerance) {
		return null;
	}

	// Escort discipline: never push further forward if already too far from the
	// human, or if there is combat right here.
	if (human != null) {
		local maxSep = GxLdBot.Settings.MaxSeparation;
		if ("cardMaxSeparationAdd" in profile) {
			maxSep += profile.cardMaxSeparationAdd;
		}
		if (maxSep < 300.0) {
			maxSep = 300.0;
		}
		local hardCap = GxLdBot.Settings.MaxSeparation + 120.0;
		if (maxSep > hardCap) {
			maxSep = hardCap;
		}
		if (GxLdBot.DistanceBetween(bot, human) > maxSep) {
			return null;
		}
		if (("ScoutCombatNearby" in GxLdBot) && GxLdBot.ScoutCombatNearby(bot, human)) {
			return null;
		}
	}

	// Throttle the (relatively costly) flow scan; reuse the cached target while
	// it is still ahead of us and we have not arrived yet.
	local idx = bot.GetEntityIndex();
	local last = (idx in GxLdBot.LastScout) ? GxLdBot.LastScout[idx] : -999.0;
	if ((now - last) < GxLdBot.Settings.ProgressInterval &&
			(idx in GxLdBot.LastScoutTarget) && GxLdBot.LastScoutTarget[idx] != null) {
		local cached = GxLdBot.LastScoutTarget[idx];
		local cacheHit = false;
		try {
			if (("flow" in cached) && botFlow < (cached.flow - GxLdBot.Settings.ProgressFlowTolerance) &&
					("pos" in cached) && cached.pos != null &&
					(origin - cached.pos).Length() > GxLdBot.Settings.ProgressRetargetDistance) {
				return cached.pos;
			}
		} catch (e2) {}
		// Cache stale (arrived or flow caught up) — force rescan immediately.
		GxLdBot.SetTableSlot(GxLdBot.LastScout, idx, -999.0);
	}

	local target = GxLdBot.BestForwardArea(bot, botFlow, targetFlow);
	GxLdBot.SetTableSlot(GxLdBot.LastScout, idx, now);
	if (target == null) {
		GxLdBot.SetTableSlot(GxLdBot.LastScoutTarget, idx, null);
		return null;
	}
	local tflow = GxLdBot.GetFlowFor(target);
	GxLdBot.SetTableSlot(GxLdBot.LastScoutTarget, idx,
		{ pos = target, flow = (tflow != null) ? tflow : targetFlow });

	try {
		if ((origin - target).Length() < GxLdBot.Settings.ProgressRetargetDistance) {
			return null; // basically already there
		}
	} catch (e3) {}

	GxLdBot.Log("progress " + profile.name + " botFlow=" + botFlow +
		" target=" + targetFlow + " lead=" + GxLdBot.LeadFlowFor(profile));
	return target;
}

// Debug print: each bot's flow vs its target lead, so you can see WHY a bot is
// pushing forward or holding.
function GxLdBot::PrintProgress(player) {
	local any = false;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		any = true;
		local profile = GxLdBot.GetProfile(bot);
		local bf = null;
		try { bf = GxLdBot.GetFlowFor(bot.GetOrigin()); } catch (e) {}
		local hf = GxLdBot.HumanMaxFlow();
		local lead = (profile != null) ? GxLdBot.LeadFlowFor(profile) : 0.0;
		GxLdBot.Chat(player, GxLdBot.SafeName(bot) +
			" flow=" + ((bf != null) ? bf : "n/a") +
			" humanFlow=" + ((hf != null) ? hf : "n/a") +
			" lead=" + lead);
	});
	if (!any) {
		GxLdBot.Chat(player, "no survivor bots");
	}
	if (!GxLdBot.Settings.EnableProgress) {
		GxLdBot.Chat(player, "progress is OFF (!hbot_progress to enable)");
	}
}
