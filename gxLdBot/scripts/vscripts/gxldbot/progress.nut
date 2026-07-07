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

// FALLBACK: the original radius scan. Kept as a fail-safe for maps where nav
// adjacency is unavailable (GetAdjacentAreas returns nothing).撒网扫描: query
// every nav area within ProgressScanRadius and pick the best forward one. This is
// the expensive path (up to ProgressMaxAreas flow lookups) that the gradient
// walker below replaces on maps where adjacency works.
function GxLdBot::BestForwardAreaScan(bot, botFlow, targetFlow) {
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

// Collect all nav areas adjacent to `area` across all 4 directions into `out`
// (keyed by area, value = the area). GetAdjacentAreas(dir, table) takes a
// direction enum 0..3 (verified in-game via hbot_navprobe: dir 0..3 each return
// neighbors). Returns the count found.
function GxLdBot::CollectAdjacent(area, out) {
	local count = 0;
	for (local dir = 0; dir < 4; dir++) {
		local adj = {};
		try {
			area.GetAdjacentAreas(dir, adj);
		} catch (e) {
			continue;
		}
		foreach (k, a in adj) {
			if (a == null) { continue; }
			// Key by integer area ID, NOT the area instance: Squirrel table keys on
			// native instance handles are not reliable for identity/dedup (the ref
			// mod always uses GetID()). Value stays the area so callers can use it.
			local aid = null;
			try { aid = a.GetID(); } catch (eid) { continue; }
			if (aid != null && !(aid in out)) {
				out[aid] <- a;
				count++;
			}
		}
	}
	return count;
}

// GRADIENT ASCENT (layer-2, verified viable via hbot_navprobe: +106 flow to an
// adjacent area). Instead of scanning every nav area in a big radius (~96 flow
// lookups), walk the nav graph from the bot's current area toward higher flow one
// hop at a time, up to ProgressGradientSteps hops. Each hop only inspects a
// handful of neighbors (~5), so this is roughly an order of magnitude cheaper than
// BestForwardAreaScan — THE fix for the progress PERF spikes. Returns the center
// of the furthest area we climbed to (still under the targetFlow ceiling), or null
// to signal "fall back to the radius scan" when adjacency is unavailable.
function GxLdBot::BestForwardArea(bot, botFlow, targetFlow) {
	local startArea = null;
	try { startArea = bot.GetLastKnownArea(); } catch (e) {}
	if (startArea == null) {
		// No area handle — can't gradient-walk; let the caller use the scan.
		return GxLdBot.BestForwardAreaScan(bot, botFlow, targetFlow);
	}

	local minGain = GxLdBot.Settings.ProgressMinAdvanceFlow;
	local maxSteps = ("ProgressGradientSteps" in GxLdBot.Settings)
		? GxLdBot.Settings.ProgressGradientSteps : 4;

	local current = startArea;
	local currentFlow = botFlow;
	local best = null;        // furthest acceptable spot found so far
	// visited is keyed by area GetID() (integer) — NOT the area instance. Native
	// instance handles are not reliable table keys in Squirrel (the reference mod
	// always keys nav areas by GetID), so we do the same to avoid a silent
	// dedup-failure that could loop the walk.
	local visited = {};
	try { visited[current.GetID()] <- true; } catch (e) {}
	local hopsFound = 0;

	for (local step = 0; step < maxSteps; step++) {
		local neighbors = {};
		local n = GxLdBot.CollectAdjacent(current, neighbors);
		if (n <= 0) {
			break; // no adjacency from here
		}

		// Pick the neighbor with the highest flow that does NOT overshoot our lead
		// ceiling and is genuinely forward. This is the ascent step.
		local bestNext = null;
		local bestNextFlow = currentFlow;
		local bestNextSpot = null;
		local bestNextId = -1;
		foreach (k, a in neighbors) {
			// k is the neighbor's GetID() (CollectAdjacent keys by ID).
			if (k in visited) { continue; }
			try {
				if (("IsBlocked" in a) && (a.IsBlocked(2, false) || a.IsBlocked(2, true))) {
					continue;
				}
			} catch (eb) {}
			local spot = null;
			try { spot = a.GetCenter(); } catch (ec) { continue; }
			if (spot == null) { continue; }
			local f = GxLdBot.GetFlowFor(spot);
			if (f == null) { continue; }
			if (f > targetFlow + 60.0) {
				continue; // past our allowed lead — don't climb toward the exit
			}
			if (f > bestNextFlow) {
				bestNextFlow = f;
				bestNext = a;
				bestNextSpot = spot;
				bestNextId = k;
			}
		}

		if (bestNext == null) {
			break; // no higher-flow neighbor under the ceiling — stop climbing
		}

		// Accept this hop.
		visited[bestNextId] <- true;
		current = bestNext;
		currentFlow = bestNextFlow;
		hopsFound++;
		// Only treat it as a usable target once it's meaningfully ahead of the bot.
		if (bestNextFlow > botFlow + minGain) {
			best = bestNextSpot;
		}
	}

	// If the gradient walk produced nothing usable (e.g. adjacency worked but every
	// neighbor was blocked/backward), fall back to the radius scan so we never
	// silently stop leading on an odd map.
	if (best == null && hopsFound == 0) {
		return GxLdBot.BestForwardAreaScan(bot, botFlow, targetFlow);
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

	// Only forward-pressure roles (point/flanker) probe ahead of a parked human;
	// anchor/follower stay tethered so we never pull an unsupportable bot off the
	// front (DESIGN 6.1 / 5.4 防孤立).
	local isScout = ("IsScoutRole" in GxLdBot) && GxLdBot.IsScoutRole(profile);

	// DYNAMIC ADVANCE (player request "few zombies -> push faster, many -> slow but
	// don't stop"). Grade the combat around this scout: 0 clear, 1 light (commons
	// crowding, no special), 2 heavy (special/witch or a real swarm). Severity 2
	// still fully stops the advance below (safety); severity 1 lets it keep moving
	// but shrinks the forward lead so it presses on cautiously instead of halting
	// for a couple of trash commons.
	local combatSev = 0;
	if (("ScoutCombatSeverity" in GxLdBot)) {
		combatSev = GxLdBot.ScoutCombatSeverity(bot, human);
	} else if (("ScoutCombatNearby" in GxLdBot) && GxLdBot.ScoutCombatNearby(bot, human)) {
		combatSev = 2; // fail-safe: no grader -> treat any combat as a hard stop
	}

	// PROACTIVE LEAD + SCOUT FORMATION (player's "I get lost on third-party maps, I
	// want a bot walking ahead as a guide, not waiting for me to point the way").
	// A scout carries a constant forward lead so it stays ahead as a living
	// breadcrumb even while you creep along. We split it by role to build a depth
	// formation: the POINT bot is the tip-of-spear guide (full ScoutLeadFlow, walks
	// furthest ahead — follow it and you're going the right way, flow always climbs
	// toward the exit); the FLANKER is a mid relay (a fraction of it) so it bridges
	// between you and the point instead of both bunching at the same distance.
	// Anchor/follower get nothing — they stay tethered as the rear guard (防孤立铁律).
	if (isScout) {
		local roleLead = GxLdBot.Settings.ScoutLeadFlow;
		if (profile.role == "flanker") {
			local mul = ("ScoutFlankerLeadMul" in GxLdBot.Settings)
				? GxLdBot.Settings.ScoutFlankerLeadMul : 0.5;
			roleLead = roleLead * mul;
		}
		targetFlow += roleLead;
	}

	// Light combat (severity 1): keep advancing but shrink the lead so the bot
	// presses forward cautiously rather than sprinting into a crowd. Multiplies the
	// slice of targetFlow that sits AHEAD of the human, leaving base flow intact.
	if (combatSev == 1 && humanFlow != null && targetFlow > humanFlow) {
		local slowMul = ("DynamicSlowLeadMul" in GxLdBot.Settings)
			? GxLdBot.Settings.DynamicSlowLeadMul : 0.5;
		targetFlow = humanFlow + (targetFlow - humanFlow) * slowMul;
	}

	// Stall probe — THE §6.1 fix. When the human has been parked past
	// ActiveAdvanceDelay, a scout pushes FURTHER to peek ahead. The old code added
	// ActiveAdvanceFlowBoost but then let a fixed ProgressMaxLeadFlow ceiling slap
	// it straight back; we RAISE the ceiling by StallProbeExtraFlow while stalled,
	// scout-only, so bots actually reach ahead instead of clamping to human flow.
	local stalled = hasHuman && (now - GxLdBot.LastTeamMoveTime) >= GxLdBot.Settings.ActiveAdvanceDelay;
	if (stalled && isScout) {
		targetFlow += GxLdBot.Settings.ActiveAdvanceFlowBoost;
	}
	// Cap: scouts may lead out to the raised ceiling; the centroid/dispersion
	// backstop below is the real isolation guard, so a generous flow cap is safe.
	if (isScout) {
		local maxTarget = baseFlow + GxLdBot.Settings.ProgressMaxLeadFlow +
			GxLdBot.Settings.StallProbeExtraFlow;
		if (targetFlow > maxTarget) {
			targetFlow = maxTarget;
		}
	}

	// EXIT-SAFEROOM GUARD (DESIGN 5.5 point-of-no-return, #5 通关级 bug): once a
	// survivor is inside the exit checkpoint, flow keeps rising into/through the
	// door, so the strong forward lead used to shove a bot PAST the finish trigger
	// into the dead zone behind it — then the human closes the door and the map is
	// unwinnable with a bot stuck outside. While anyone is in the exit checkpoint,
	// never let a bot's target flow exceed the human's: it may keep pace to the
	// door but never run through it ahead of the player, who decides when to enter.
	if (hasHuman && humanFlow != null && GxLdBot.Settings.EndpointHoldEnable
			&& ("AnyoneInExitSaferoom" in GxLdBot) && GxLdBot.AnyoneInExitSaferoom()) {
		local endCap = humanFlow + GxLdBot.Settings.EndpointHoldFlowMargin;
		if (targetFlow > endCap) {
			targetFlow = endCap;
		}
	}

	// Already at/past our allowed lead. If we're a scout who has genuinely walked
	// AHEAD of the human (leading), don't hand back to vanilla — vanilla's follow
	// then walks us straight back to the human, which is the "来回蹭" shuffle the
	// player complained about. Instead return a GUIDE-HOLD: stop here and face the
	// human ("walked ahead, now I turn and wait / point the way"). Only when it's
	// safe (no combat, not isolated); otherwise fall through to vanilla as before.
	if (botFlow >= targetFlow - GxLdBot.Settings.ProgressFlowTolerance) {
		// Guide-hold whenever this scout is genuinely AHEAD of the human (humanFlow <
		// botFlow), moving or not. THE FIX for weak lead feel: the old code required
		// !humanMoving here, so the moment you pressed W the scout skipped guide and
		// returned null → vanilla follow yanked it back to your side (the "来回蹭 /
		// no lead feel" shuffle). By holding the forward spot while you move, the bot
		// stays out front as a breadcrumb and you walk up BEHIND it — then it re-pushes
		// as you close the gap. Guarded by dispersion + no heavy combat so we never
		// strand it. When the human passes the bot (humanFlow >= botFlow) this fails
		// and progress re-pushes the bot ahead again.
		if (isScout && human != null && humanFlow != null && humanFlow < botFlow
				&& GxLdBot.BotCentroidDispersion(bot) <= GxLdBot.Settings.SquadDispersionMax
				&& combatSev < 2) {
			return { guide = true, human = human };
		}
		return null;
	}

	// Isolation backstop (DESIGN 5.4 / 6.2): if this bot is already the outlier
	// (furthest from the squad centroid beyond SquadDispersionMax), never push it
	// further forward — escort's 回身 check will pull it home instead. This catches
	// "far from EVERYONE and unsupportable," which the bot-to-human leash misses
	// when the human themselves has run off.
	if (GxLdBot.BotCentroidDispersion(bot) > GxLdBot.Settings.SquadDispersionMax) {
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
		// During a stall probe a scout is allowed to range further from the human
		// (that's the point — go look ahead). The bot-to-human leash widens up to
		// SquadDispersionMax; the centroid backstop above is the real isolation
		// guard, so widening here can't create an unsupportable outlier.
		// A SCOUT is allowed to range out to the guide distance at ALL times (not
		// just during a stall), so it can walk ahead as a breadcrumb while you move
		// too — without escort yanking it back at MaxSeparation (that yank was the
		// "creep forward / get pulled back" shuffle). The centroid backstop above is
		// the real isolation guard, so widening the human leash here is safe.
		local hardCap = GxLdBot.Settings.MaxSeparation + 120.0;
		if (isScout && GxLdBot.Settings.SquadDispersionMax > hardCap) {
			hardCap = GxLdBot.Settings.SquadDispersionMax;
		}
		if (maxSep > hardCap) {
			maxSep = hardCap;
		}
		if (GxLdBot.DistanceBetween(bot, human) > maxSep) {
			return null;
		}
		// Dynamic advance: only a HEAVY threat (severity 2 — special/witch or a real
		// swarm) fully stops forward pressure. Light crowding (severity 1) already
		// had its lead throttled above, so the bot keeps advancing, just slower.
		if (combatSev >= 2) {
			return null;
		}
	}

	// Throttle the (relatively costly) flow scan; reuse the cached target while
	// it is still ahead of us and we have not arrived yet. While the human is
	// MOVING we cut the interval (ScoutMovingInterval) so the scout re-targets
	// crisply and stays ahead instead of lagging a beat behind a walking player
	// (the "bot reacts slowly / trails me" feel). Parked human keeps the cheaper
	// full interval.
	local idx = bot.GetEntityIndex();
	local scanInterval = GxLdBot.Settings.ProgressInterval;
	if (("HumanIsMoving" in GxLdBot) && GxLdBot.HumanIsMoving()
			&& ("ScoutMovingInterval" in GxLdBot.Settings)) {
		scanInterval = GxLdBot.Settings.ScoutMovingInterval;
	}
	local last = (idx in GxLdBot.LastScout) ? GxLdBot.LastScout[idx] : -999.0;
	if ((now - last) < scanInterval &&
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

// ---- LAYER-2 NAV-API PROBE (read-only diagnostic, DESIGN perf roadmap) ------
//
// Verifies whether the flow-gradient-ascent APIs work in THIS sandbox before we
// rewrite BestForwardArea to use them. Rewrites nothing; just runs each API on a
// real survivor bot and reports what succeeded, so we learn in ONE game launch
// whether "walk the adjacency graph up-flow" (cheap) can replace "scan all nav
// areas in a big radius" (the 7-12ms cost). Chat-only output.
//
// The four things we must confirm:
//   1. GetLastKnownArea() returns a usable area on a bot
//   2. area.GetID()/GetCenter() work
//   3. area.GetAdjacentAreas(dir, table) fills a table (and how many dirs exist)
//   4. we can read flow at adjacent-area centers and see a gradient to climb
function GxLdBot::NavProbe(player) {
	GxLdBot.Chat(player, "==== nav-probe (layer-2 API check) ====");

	local bot = null;
	GxLdBot.ForEachSurvivorBot(function(b) {
		if (bot == null && GxLdBot.IsAlive(b)) { bot = b; }
	});
	if (bot == null) {
		GxLdBot.Chat(player, "no alive survivor bot to probe");
		return;
	}
	GxLdBot.Chat(player, "probing on: " + GxLdBot.SafeName(bot));

	// 1) GetLastKnownArea
	local area = null;
	try {
		area = bot.GetLastKnownArea();
	} catch (e) {
		GxLdBot.Chat(player, "1) GetLastKnownArea THREW: " + e);
		return;
	}
	if (area == null) {
		GxLdBot.Chat(player, "1) GetLastKnownArea = null (bot off-mesh?) — abort");
		return;
	}
	GxLdBot.Chat(player, "1) GetLastKnownArea OK");

	// 2) GetID / GetCenter / flow at center
	local baseFlow = null;
	try {
		local id = area.GetID();
		local ctr = area.GetCenter();
		baseFlow = GxLdBot.GetFlowFor(ctr);
		GxLdBot.Chat(player, "2) area id=" + id + " centerFlow=" +
			((baseFlow != null) ? baseFlow : "n/a"));
	} catch (e2) {
		GxLdBot.Chat(player, "2) GetID/GetCenter THREW: " + e2);
		return;
	}

	// 3) GetAdjacentAreas across directions 0..3, count neighbors + best up-flow.
	// If direction is a single enum we still cover it by looping 0..3.
	local totalAdj = 0;
	local bestUpFlow = baseFlow;
	local bestDir = -1;
	for (local dir = 0; dir < 4; dir++) {
		local adj = {};
		local ok = false;
		try {
			area.GetAdjacentAreas(dir, adj);
			ok = true;
		} catch (e3) {
			GxLdBot.Chat(player, "3) GetAdjacentAreas(dir=" + dir + ") THREW: " + e3);
		}
		if (!ok) { continue; }
		local cnt = 0;
		foreach (a in adj) {
			cnt++;
			try {
				local f = GxLdBot.GetFlowFor(a.GetCenter());
				if (f != null && (bestUpFlow == null || f > bestUpFlow)) {
					bestUpFlow = f;
					bestDir = dir;
				}
			} catch (e4) {}
		}
		totalAdj += cnt;
		GxLdBot.Chat(player, "3) dir=" + dir + " neighbors=" + cnt);
	}
	GxLdBot.Chat(player, "3) total adjacent areas=" + totalAdj);

	// 4) gradient verdict
	if (totalAdj <= 0) {
		GxLdBot.Chat(player, "4) NO adjacency returned — gradient ascent NOT viable, keep radius scan");
	} else if (baseFlow != null && bestUpFlow != null && bestUpFlow > baseFlow) {
		GxLdBot.Chat(player, "4) up-flow neighbor found (+" + (bestUpFlow - baseFlow) +
			" flow, dir=" + bestDir + ") — GRADIENT ASCENT VIABLE");
	} else {
		GxLdBot.Chat(player, "4) adjacency works but no higher-flow neighbor here (may be at a peak/flat)");
	}
	GxLdBot.Chat(player, "==== end nav-probe ====");
}
