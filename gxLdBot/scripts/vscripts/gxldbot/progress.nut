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

// ---- CRASH BLACK BOX (diagnostic, temporary) --------------------------------
// The player reports occasional hard crashes at specific map nodes. minidumps
// have no symbols so we can't read the native stack. Instead we mark the moment
// right before each native NavMesh call that runs every frame, flushing a single
// line to disk immediately. If the engine crashes INSIDE one of these native
// calls, Squirrel try/catch cannot catch it — but the last line left in
// gxldbot/blackbox.txt names exactly which call was in flight. Remove once the
// crash source is identified. Gated by BlackBoxEnable so it's zero-cost when off.
function GxLdBot::BlackBox(tag) {
	if (!("BlackBoxEnable" in GxLdBot.Settings) || !GxLdBot.Settings.BlackBoxEnable) {
		return;
	}
	try {
		StringToFile("gxldbot/blackbox.txt",
			GxLdBot.Now().tostring() + " " + tag + "\n");
	} catch (e) {}
}

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

// Lowest flow among ALL alive survivors (bots included) — i.e. how far the most
// straggling team member has progressed. Used by the regroup clamp: on slow
// terrain (swamp mud) the rear falls behind because everyone's absolute speed is
// throttled by the engine while the point keeps pushing on flow; comparing the
// lead against this min tells us the squad is stretched so the point should ease
// off and let the straggler close the gap. Flow-based, so it stays correct on
// slow terrain (a lagging bot's flow simply climbs slower) without depending on
// any speed NetProp. Returns null when no flow is available (finale/survival).
function GxLdBot::TeamMinFlow() {
	local worst = null;
	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s)) {
			return;
		}
		local f = null;
		try { f = GxLdBot.GetFlowFor(s.GetOrigin()); } catch (e) {}
		if (f != null && (worst == null || f < worst)) {
			worst = f;
		}
	});
	return worst;
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
			best = { area = area, pos = spot, flow = f,
				parentArea = null, source = "scan" };
		}
	}
	return best;
}

// Validate a fidget hold-shift point before we command a bot to it. The guide/
// fidget code generates a small random XY offset off the arrival spot; on maps
// with railings, ledges, doorways or one-way drops that raw point can land in a
// wall, off-mesh, over a cliff edge, or in acid/fire — CommandABot then
// micro-paths, jitters, or walks the point somewhere bad.
//
// HONEST SCOPE (per review): this is a HEURISTIC, not a proof. We accept the
// point only if there is a nav area whose center is very close to it (tight
// radius), on roughly the same floor (small Z band), not blocked, and not
// damaging. It does NOT prove the raw point lies inside that area, nor that the
// straight line base->point is walkable (no railing/thin-wall between). It
// meaningfully cuts the off-mesh / cliff / acid cases vs feeding the raw random
// point, and the offset is tiny (<=FidgetRadius) so the residual risk is small,
// but it is not a hard guarantee. Returns true if safe enough to use; false
// means "skip this fidget, hold the base spot".
function GxLdBot::FidgetPointSafe(pos, baseZ) {
	if (pos == null) {
		return false;
	}
	local areas = {};
	GxLdBot.BlackBox("fidget.GetNavAreasInRadius BEFORE");
	try {
		// Tight radius: we want a nav area essentially UNDER the point, not just
		// "somewhere nearby" (a loose radius would accept a point across a railing
		// gap). Smaller than a nav grid step so a match implies the point is
		// approximately on-mesh, not merely near a distinct neighboring area.
		NavMesh.GetNavAreasInRadius(pos, 25.0, areas);
	} catch (e) {
		return false; // API unavailable / threw — fail closed, don't fidget
	}
	GxLdBot.BlackBox("fidget.GetNavAreasInRadius AFTER");
	local ok = false;
	foreach (area in areas) {
		if (area == null) { continue; }
		try {
			if (("IsBlocked" in area) && (area.IsBlocked(2, false) || area.IsBlocked(2, true))) {
				continue;
			}
		} catch (eb) {}
		// Reject damaging areas (acid/fire): a fidget must never step the point into
		// a hazard just to look alive.
		try {
			if (!("IsDamaging" in area) || area.IsDamaging()) {
				continue;
			}
		} catch (ed) { continue; }
		local ctr = null;
		try { ctr = area.GetCenter(); } catch (ec) { continue; }
		if (ctr == null) { continue; }
		// Same-floor guard: reject areas whose center is far above/below the base
		// hold spot, so a fidget never steps onto a ledge above or a drop below.
		local dz = ctr.z - baseZ;
		if (dz < 0.0) { dz = -dz; }
		if (dz > 45.0) { continue; }
		ok = true;
		break;
	}
	return ok;
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
	local best = null;        // furthest acceptable area record found so far
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
		local parentArea = current;
		visited[bestNextId] <- true;
		current = bestNext;
		currentFlow = bestNextFlow;
		hopsFound++;
		// Only treat it as a usable target once it's meaningfully ahead of the bot.
		if (bestNextFlow > botFlow + minGain) {
			best = { area = bestNext, pos = bestNextSpot, flow = bestNextFlow,
				parentArea = parentArea, source = "gradient" };
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

function GxLdBot::ReversePathAreaToHuman(candidateArea, human, label = "candidate", budgetOwned = false) {
	if (!GxLdBot.Settings.ReversePathEnable || candidateArea == null ||
			human == null || !GxLdBot.IsValidEntity(human)) {
		return false;
	}
	local humanArea = null;
	try { humanArea = human.GetLastKnownArea(); } catch (e) {}
	if (humanArea == null) { return false; }
	local candidateId = -1;
	local humanId = -1;
	try { candidateId = candidateArea.GetID(); humanId = humanArea.GetID(); } catch (eid) { return false; }
	local key = candidateId + ">" + humanId;
	local now = GxLdBot.Now();
	if (key in GxLdBot.ReversePathCache) {
		local cached = GxLdBot.ReversePathCache[key];
		if ((now - cached.at) < GxLdBot.Settings.ReversePathCacheSeconds) { return cached.ok; }
	}
	// A cache miss means we are about to run NavAreaBuildPath — a heavy query.
	// budgetOwned=true means the CALLER already claimed this tick's heavy slice for
	// the very operation this path-check belongs to (the fresh BestForwardArea scan
	// that just claimed a HeavySliceCount slot): the reverse-path validation of that freshly
	// computed target is part of the SAME work unit, so we must NOT fail it closed —
	// doing so would reject every fresh far target and cap the point at
	// UnprovenForwardMaxDistance forever. Only a STANDALONE reverse-path (cached
	// target re-check, guide/escort leash) is heavy work of its own: for those,
	// budgetOwned=false and we gate — if the slice is spent, fail CLOSED (hold this
	// tick, the next free tick runs it). This closes the leak GPT flagged without
	// breaking the far-lead handfeel.
	if (!budgetOwned) {
		local sliceMax = ("HeavySliceMax" in GxLdBot.Settings) ? GxLdBot.Settings.HeavySliceMax : 3;
		if (("HeavySliceCount" in GxLdBot) && GxLdBot.HeavySliceCount >= sliceMax) {
			// THREE-STATE: no heavy budget this tick, so we did NOT run the path build.
			// Return null ("unknown"), NOT false ("proven unreachable"). Callers that
			// PUSH FORWARD treat null as reject (fail-closed, correct). Callers that
			// PULL A POINT BACK must treat null as "don't retract this tick" — collapsing
			// no-budget into false is what let escort yank a far point home merely because
			// we were out of budget that tick (the periodic-retract regression).
			return null;
		}
		GxLdBot.HeavySliceCount = ("HeavySliceCount" in GxLdBot) ? GxLdBot.HeavySliceCount + 1 : 1;
	}
	local ok = false;
	GxLdBot.ReversePathStats.calls++;
	// BLACK BOX (crash diagnosis): NavAreaBuildPath is a native engine call; if it
	// faults on a specific map's nav geometry, a Squirrel try/catch CANNOT catch it
	// (the process dies inside the engine). We stamp a marker to a file that is
	// flushed to disk BEFORE the call. After a crash, if blackbox.txt's last line is
	// this "navpath:before" marker with no matching "after", this call is the crash
	// site — the smoking gun a symbol-less minidump can't give us.
	GxLdBot.BlackBox("navpath:before c=" + candidateId + " h=" + humanId + " len=" +
		GxLdBot.Settings.ReversePathMaxLength);
	try {
		ok = NavMesh.NavAreaBuildPath(candidateArea, humanArea, human.GetOrigin(),
			GxLdBot.Settings.ReversePathMaxLength, 2, false);
		GxLdBot.BlackBox("navpath:after ok=" + ok);
		if (ok) { GxLdBot.ReversePathStats.ok++; }
		else { GxLdBot.ReversePathStats.rejected++; }
	} catch (e2) {
		GxLdBot.ReversePathStats.errors++;
		GxLdBot.Log("reverse_path " + label + " failed: " + e2, true);
		ok = false;
	}
	GxLdBot.SetTableSlot(GxLdBot.ReversePathCache, key, { ok = ok, at = now });
	if (GxLdBot.Settings.ReversePathProbeDebug) {
		GxLdBot.Log("reverse_path " + label + " " + candidateId + "->" + humanId + " ok=" + ok, true);
	}
	return ok;
}

function GxLdBot::CurrentPositionReversePathSafe(bot, human) {
	if (!GxLdBot.IsValidEntity(bot)) { return false; }
	local area = null;
	try { area = bot.GetLastKnownArea(); } catch (e) {}
	return GxLdBot.ReversePathAreaToHuman(area, human, "current");
}

// Fixed-order Safety Gate for optional forward movement. A nearby gradient
// candidate may use the conservative envelope; a farther candidate must prove a
// candidate->human reverse path. Unknown path state always fails closed.
function GxLdBot::ProgressCandidateSafe(bot, candidate, human, formationSlot, budgetOwned = false) {
	if (!GxLdBot.IsValidEntity(bot) || candidate == null ||
			typeof candidate != "table" || !("pos" in candidate) || candidate.pos == null) {
		return false;
	}
	// Candidate SELF-safety (source / area exists / not blocked / not damaging) is
	// intrinsic to the point and must run whether or not a human is alive. Only the
	// human-connectivity checks below (reverse path, support link, claim) are gated
	// on having a human. Previously an early `human==null -> return true` skipped ALL
	// of these, so an all-bot game / dead-human single-player could accept a
	// radius-scan candidate sitting in a damaging/off-mesh area (GPT P1#2).
	if (("source" in candidate) && candidate.source != "gradient") {
		return false; // radius scan cannot prove connectivity on third-party maps
	}
	if (!("area" in candidate) || candidate.area == null) {
		return false;
	}
	try {
		if (!("IsBlocked" in candidate.area) ||
				candidate.area.IsBlocked(2, false) || candidate.area.IsBlocked(2, true)) {
			return false;
		}
	} catch (e) { return false; }
	try {
		if (!("IsDamaging" in candidate.area) || candidate.area.IsDamaging()) {
			return false;
		}
	} catch (e2) { return false; }

	// No alive human: candidate self-safety passed above; the human-connectivity
	// gates (reverse path / support link / claim) are N/A, so accept (preserves
	// all-bot self-complete behavior without skipping intrinsic safety).
	if (human == null || !GxLdBot.IsValidEntity(human)) {
		return true;
	}

	if (formationSlot == "point") {
		try {
			local leadDistance = (candidate.pos - human.GetOrigin()).Length();
			if (leadDistance > GxLdBot.Settings.ReversePathMaxLeadDistance) {
				return false;
			}
			if (leadDistance > GxLdBot.Settings.UnprovenForwardMaxDistance) {
				if (!GxLdBot.ReversePathAreaToHuman(candidate.area, human, "forward", budgetOwned)) {
					return false;
				}
			} else {
				local drop = bot.GetOrigin().z - candidate.pos.z;
				if (drop > GxLdBot.Settings.UnprovenForwardMaxDrop) { return false; }
			}
		} catch (e3) { return false; }
	}

	local targetFlow = ("flow" in candidate) ? candidate.flow : GxLdBot.GetFlowFor(candidate.pos);
	if (("TargetHasHumanSupport" in GxLdBot) &&
			!GxLdBot.TargetHasHumanSupport(bot, candidate.pos, targetFlow)) {
		return false;
	}
	local claimKey = (formationSlot == "point") ? "advance:point" :
		((formationSlot == "relay") ? "formation:relay" : null);
	if (claimKey != null && GxLdBot.Settings.EnableClaims) {
		if (!(claimKey in GxLdBot.Claims) ||
				GxLdBot.Claims[claimKey].owner != bot.GetEntityIndex() ||
				(GxLdBot.Now() - GxLdBot.Claims[claimKey].time) >= GxLdBot.Settings.ClaimExpiry) {
			return false;
		}
	}
	return true;
}

function GxLdBot::FormationHoldIntent(bot, formationSlot, human, humanFlow, botFlow, combatSev) {
	if (human == null || humanFlow == null || botFlow == null ||
			humanFlow >= botFlow || combatSev >= 2) {
		return null;
	}
	local origin = null;
	try { origin = bot.GetOrigin(); } catch (e) { return null; }
	if (("TargetHasHumanSupport" in GxLdBot) &&
			!GxLdBot.TargetHasHumanSupport(bot, origin, botFlow)) {
		return null;
	}
	if (formationSlot == "point") {
		local d = GxLdBot.DistanceBetween(bot, human);
		// Three-state reverse path (same rule as the guide-hold in ProgressIntentFor
		// and the escort leash): != false means "proven reachable OR not checked this
		// tick (no budget)" — either way HOLD the forward spot. Only a proven-false
		// (genuinely unreachable) result denies the far guide-hold. A bare truthiness
		// test here would treat the no-budget null as unreachable and drop a
		// legitimately-far point out of guide-hold into escort's retract (the P1#1
		// regression, second occurrence).
		if (d <= GxLdBot.Settings.UnprovenForwardMaxDistance ||
				(d <= GxLdBot.Settings.ReversePathMaxLeadDistance &&
				GxLdBot.CurrentPositionReversePathSafe(bot, human) != false)) {
			return { guide = true, human = human };
		}
	}
	if (formationSlot == "relay") {
		return { relayHold = true, human = human };
	}
	return null;
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
	if (("BotAllowsProgress" in GxLdBot) && !GxLdBot.BotAllowsProgress(bot)) {
		return null;
	}

	local profile = GxLdBot.GetProfile(bot);
	if (profile == null) {
		return null;
	}
	local formationSlot = ("FormationSlotFor" in GxLdBot)
		? GxLdBot.FormationSlotFor(bot) : ((profile.role == "point") ? "point" : "none");
	local isPoint = formationSlot == "point";
	local isRelay = formationSlot == "relay";
	// A human-led buddy formation has exactly one autonomous point and one relay.
	// Rear/flex stay on vanilla/escort instead of independently acquiring the same
	// progress target and turning the squad into a synchronized forward swarm.
	if (hasHuman && !isPoint && !isRelay) {
		return null;
	}
	if (isPoint && !GxLdBot.TryClaim("advance:point", bot)) { return null; }
	if (isRelay && !GxLdBot.TryClaim("formation:relay", bot)) { return null; }
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
	local targetFlow = baseFlow;
	local now = GxLdBot.Now();
	if (isPoint && (bot.GetEntityIndex() in GxLdBot.GuideCooldownUntil) &&
			now < GxLdBot.GuideCooldownUntil[bot.GetEntityIndex()]) {
		return null;
	}

	if (isRelay) {
		// Relay owns a real second lead. Base it on the point's proactive budget as
		// well as its current position, so both leaders start moving together instead
		// of the relay waiting to chase the point's heels.
		if (humanFlow == null || !("FormationEntityFor" in GxLdBot)) {
			return null;
		}
		local point = GxLdBot.FormationEntityFor("point");
		if (point == null || point == bot) {
			return null;
		}
		local pointFlow = null;
		try { pointFlow = GxLdBot.GetFlowFor(point.GetOrigin()); } catch (ep) {}
		if (pointFlow == null) {
			return null;
		}
		local pointLead = pointFlow - humanFlow;
		local pointProfile = GxLdBot.GetProfile(point);
		if (pointProfile != null) {
			local plannedLead = GxLdBot.LeadFlowFor(pointProfile) + GxLdBot.Settings.ScoutLeadFlow;
			if (plannedLead > pointLead) { pointLead = plannedLead; }
		}
		if (pointLead <= GxLdBot.Settings.ProgressMinAdvanceFlow) { return null; }
		local frac = GxLdBot.Settings.RelayFlowFraction;
		targetFlow = humanFlow + (pointLead * frac);
	} else {
		// Only the point owns the personality/card lead and proactive scout budget.
		targetFlow = baseFlow + GxLdBot.LeadFlowFor(profile) + GxLdBot.Settings.ScoutLeadFlow;
	}

	// DYNAMIC ADVANCE (player request "few zombies -> push faster, many -> slow but
	// don't stop"). Grade the combat around this scout: 0 clear, 1 light (commons
	// crowding, no special), 2 heavy (special/witch or a real swarm). Severity 2
	// still fully stops the advance below (safety); severity 1 lets it keep moving
	// but shrinks the forward lead so it presses on cautiously instead of halting
	// for a couple of trash commons.
	local combatSev = 0;
	if ("GetSituation" in GxLdBot) {
		local frame = GxLdBot.GetSituation();
		if (frame.specialEvidence || frame.commonEvidence >= GxLdBot.Settings.DynamicHeavyCommonCount) {
			combatSev = 2;
		} else if (frame.commonEvidence >= GxLdBot.Settings.DynamicSlowCommonCount) {
			combatSev = 1;
		}
	} else if (("ScoutCombatSeverity" in GxLdBot)) {
		combatSev = GxLdBot.ScoutCombatSeverity(bot, human);
	} else if (("ScoutCombatNearby" in GxLdBot) && GxLdBot.ScoutCombatNearby(bot, human)) {
		combatSev = 2; // fail-safe: no grader -> treat any combat as a hard stop
	}
	// AFTERMATH is a falling edge, not danger. Keep moving immediately, but reuse
	// the light-combat lead multiplier for a brief, visibly cautious recovery.
	if (combatSev < 1 && ("BotPerceivedPhase" in GxLdBot) &&
			GxLdBot.BotPerceivedPhase(bot) == "AFTERMATH") {
		combatSev = 1;
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
	if (stalled && isPoint) {
		targetFlow += GxLdBot.Settings.ActiveAdvanceFlowBoost;
	}
	if ("PlayerDirective" in GxLdBot && now < GxLdBot.PlayerDirective.until &&
			humanFlow != null && isPoint) {
		if (GxLdBot.PlayerDirective.kind == "wait") {
			local waitCap = humanFlow + GxLdBot.Settings.PlayerWaitLeadFlow;
			if (targetFlow > waitCap) { targetFlow = waitCap; }
		} else if (GxLdBot.PlayerDirective.kind == "moveon") {
			targetFlow += GxLdBot.Settings.PlayerMoveOnFlowBoost;
		}
	}
	// The point may request a generous flow ceiling, but the candidate still has
	// to pass the conservative support/distance gate below before it can move.
	if (isPoint) {
		local maxTarget = baseFlow + GxLdBot.Settings.ProgressMaxLeadFlow +
			GxLdBot.Settings.StallProbeExtraFlow;
		if (targetFlow > maxTarget) {
			targetFlow = maxTarget;
		}
	}

	// STRAGGLER REGROUP (player's "swamp / mud: everyone walks slow, the rear falls
	// behind and never catches up"). Rubber-band speed boost cannot help there — mud
	// slows via m_flLaggedMovementValue < 1.0 and the lease driver refuses to write
	// over an engine slowdown. So instead of speeding the rear up, we hold the FRONT
	// back: if a leader's target flow runs more than RegroupStretchFlow ahead of the
	// MOST-behind living teammate (TeamMinFlow — includes bots, since the straggler is
	// usually a bot), clamp the lead so the front waits for the group to close up.
	// Past RegroupHardFlow beyond stretch, pin the leader to essentially the
	// straggler's flow (a near-full stop) until the gap closes. Pure flow/distance
	// logic — works regardless of which NetProp the terrain slowdown uses. Skipped
	// while the human is the one behind (humanFlow low) is NOT desired: we anchor to
	// the straggler whoever it is, so the squad never smears out on slow terrain.
	if ((isPoint || isRelay) && ("TeamMinFlow" in GxLdBot)) {
		local minFlow = GxLdBot.TeamMinFlow();
		if (minFlow != null) {
			local stretch = ("RegroupStretchFlow" in GxLdBot.Settings)
				? GxLdBot.Settings.RegroupStretchFlow : 650.0;
			local hard = ("RegroupHardFlow" in GxLdBot.Settings)
				? GxLdBot.Settings.RegroupHardFlow : 1100.0;
			local gap = targetFlow - minFlow;
			if (gap > hard) {
				// Way too stretched — wait for the group. Pin near the straggler.
				local pinned = minFlow + stretch * 0.5;
				if (targetFlow > pinned) { targetFlow = pinned; }
			} else if (gap > stretch) {
				// Moderately stretched — stop extending the lead past the stretch band.
				local capped = minFlow + stretch;
				if (targetFlow > capped) { targetFlow = capped; }
			}
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
		// Reverse-path here is three-state: != false means "proven reachable OR not
		// checked this tick". Holding the forward guide spot is the LOW-risk action
		// (the bot just stays put and faces you), so a no-budget null should keep the
		// hold, not drop back to vanilla (which would walk it home = the retract bug).
		// Only a proven-UNREACHABLE false falls through so escort can pull it back.
		if (isPoint && human != null && humanFlow != null && humanFlow < botFlow
				&& combatSev < 2
				&& (GxLdBot.DistanceBetween(bot, human) <= GxLdBot.Settings.UnprovenForwardMaxDistance ||
					(GxLdBot.DistanceBetween(bot, human) <= GxLdBot.Settings.ReversePathMaxLeadDistance &&
					GxLdBot.CurrentPositionReversePathSafe(bot, human) != false))
				&& (!("TargetHasHumanSupport" in GxLdBot) ||
					GxLdBot.TargetHasHumanSupport(bot, origin, botFlow))) {
			return { guide = true, human = human };
		}
		if (isRelay && human != null && humanFlow != null && humanFlow < botFlow
				&& combatSev < 2
				&& (!("TargetHasHumanSupport" in GxLdBot) ||
					GxLdBot.TargetHasHumanSupport(bot, origin, botFlow))) {
			return { relayHold = true, human = human };
		}
		return null;
	}

	// Escort discipline: never push further forward if already too far from the
	// human, or if there is combat right here.
	if (human != null) {
		local maxSep = isPoint ? GxLdBot.Settings.ReversePathMaxLeadDistance
			: GxLdBot.Settings.SupportLinkDistance;
		if ("cardMaxSeparationAdd" in profile) {
			// Card separation may tighten the formation, but cannot widen the
			// unproven-path safety envelope in slice 1.
			if (profile.cardMaxSeparationAdd < 0) {
				maxSep += profile.cardMaxSeparationAdd;
			}
		}
		if (maxSep < 300.0) {
			maxSep = 300.0;
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
	if (isRelay) { scanInterval = GxLdBot.Settings.RelayProgressInterval; }
	if (("HumanIsMoving" in GxLdBot) && GxLdBot.HumanIsMoving()
			&& ("ScoutMovingInterval" in GxLdBot.Settings)) {
		scanInterval = GxLdBot.Settings.ScoutMovingInterval;
	}
	local last = (idx in GxLdBot.LastScout) ? GxLdBot.LastScout[idx] : -999.0;
	if ((now - last) < scanInterval &&
			(idx in GxLdBot.LastScoutTarget) && GxLdBot.LastScoutTarget[idx] != null) {
		local cached = GxLdBot.LastScoutTarget[idx];
		try {
			if (("flow" in cached) && botFlow < (cached.flow - GxLdBot.Settings.ProgressFlowTolerance) &&
					("pos" in cached) && cached.pos != null &&
					(origin - cached.pos).Length() > GxLdBot.Settings.ProgressRetargetDistance &&
					GxLdBot.ProgressCandidateSafe(bot, cached, human, formationSlot)) {
				GxLdBot.SetTableSlot(cached, "intentKind", isRelay ? "relay" : "progress");
				return cached;
			}
		} catch (e2) {}
		// Cache stale (arrived or flow caught up) — force rescan immediately.
		GxLdBot.SetTableSlot(GxLdBot.LastScout, idx, -999.0);
	}

	// Cooperative per-tick work budget: cap the number of heavy ops (nav expansion
	// + infected scan) per arbiter tick so we never spike the frame time. This used
	// to be a SINGLE boolean slice, which meant point and relay fought over one
	// budget and whichever lost just held — the "walk a step, stop a step" feel the
	// player reported, because the two leaders alternated moving/holding every tick.
	// It is now a COUNTER capped at HeavySliceMax (default 3): point AND relay can
	// both expand nav in the same tick (continuous lead like the early version),
	// while the cap still prevents an unbounded pile-up of heavy queries. Cached
	// targets remain usable above without consuming budget.
	local sliceMax = ("HeavySliceMax" in GxLdBot.Settings) ? GxLdBot.Settings.HeavySliceMax : 3;
	if (("HeavySliceCount" in GxLdBot) && GxLdBot.HeavySliceCount >= sliceMax) {
		return GxLdBot.FormationHoldIntent(bot, formationSlot, human,
			humanFlow, botFlow, combatSev);
	}
	GxLdBot.HeavySliceCount = ("HeavySliceCount" in GxLdBot) ? GxLdBot.HeavySliceCount + 1 : 1;
	local target = GxLdBot.BestForwardArea(bot, botFlow, targetFlow);
	GxLdBot.SetTableSlot(GxLdBot.LastScout, idx, now);
	if (target == null) {
		GxLdBot.SetTableSlot(GxLdBot.LastScoutTarget, idx, null);
		return GxLdBot.FormationHoldIntent(bot, formationSlot, human,
			humanFlow, botFlow, combatSev);
	}
	if (!GxLdBot.ProgressCandidateSafe(bot, target, human, formationSlot, true)) {
		GxLdBot.SetTableSlot(GxLdBot.LastScoutTarget, idx, null);
		return GxLdBot.FormationHoldIntent(bot, formationSlot, human,
			humanFlow, botFlow, combatSev);
	}
	if (!("flow" in target) || target.flow == null) {
		GxLdBot.SetTableSlot(target, "flow", targetFlow);
	}
	GxLdBot.SetTableSlot(target, "intentKind", isRelay ? "relay" : "progress");
	GxLdBot.SetTableSlot(GxLdBot.LastScoutTarget, idx, target);

	try {
		if ((origin - target.pos).Length() < GxLdBot.Settings.ProgressRetargetDistance) {
			// The next forward nav step is very close. Only treat this as "arrived at
			// the lead spot, hold and face the player" once the point has ESTABLISHED a
			// real body-length lead over the human (botFlow ahead by >= LeadEstablishedFlow).
			// If the bot is behind OR merely level with you (the "带路不积极" case: data
			// showed bf-hf ~+56 with the point handing back to vanilla-follow), holding is
			// wrong — FormationHoldIntent bails on a not-clearly-ahead bot and we fall back
			// to vanilla. So keep RETURNING the nearby forward target to step out front and
			// build the lead first; only hold once genuinely ahead.
			local established = GxLdBot.Settings.LeadEstablishedFlow;
			local clearlyAhead = (humanFlow != null && botFlow != null &&
				botFlow >= humanFlow + established);
			if (clearlyAhead) {
				return GxLdBot.FormationHoldIntent(bot, formationSlot, human,
					humanFlow, botFlow, combatSev);
			}
		}
	} catch (e3) {}

	GxLdBot.Log("progress " + profile.name + " botFlow=" + botFlow +
		" target=" + targetFlow + " slot=" + formationSlot +
		" lead=" + GxLdBot.LeadFlowFor(profile));
	return target;
}

// Debug print: each bot's flow vs its target lead, so you can see WHY a bot is
// pushing forward or holding.
function GxLdBot::PrintProgress(player) {
	local any = false;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		any = true;
		local profile = GxLdBot.GetProfile(bot);
		local slot = ("FormationSlotFor" in GxLdBot)
			? GxLdBot.FormationSlotFor(bot) : "none";
		local bf = null;
		try { bf = GxLdBot.GetFlowFor(bot.GetOrigin()); } catch (e) {}
		local hf = GxLdBot.HumanMaxFlow();
		local lead = (profile != null) ? GxLdBot.LeadFlowFor(profile) : 0.0;
		GxLdBot.Chat(player, GxLdBot.SafeName(bot) +
			" slot=" + slot + " flow=" + ((bf != null) ? bf : "n/a") +
			" humanFlow=" + ((hf != null) ? hf : "n/a") +
			" lead=" + lead);
	});
	GxLdBot.Chat(player, "reversePath calls=" + GxLdBot.ReversePathStats.calls +
		" ok=" + GxLdBot.ReversePathStats.ok + " reject=" +
		GxLdBot.ReversePathStats.rejected + " errors=" + GxLdBot.ReversePathStats.errors);
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
	local bestUpArea = null;
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
					bestUpArea = a;
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

	// 5) Directional path pairs. Repeat this command with the human/bot placed on
	// same floor, stairs, opposite sides of a drop, and opposite sides of a door.
	local human = GxLdBot.NearestHuman(bot);
	if (human == null) {
		GxLdBot.Chat(player, "5) no human: reverse-path pair skipped");
	} else {
		local humanArea = null;
		try { humanArea = human.GetLastKnownArea(); } catch (eh) {}
		if (humanArea == null) {
			GxLdBot.Chat(player, "5) NavAreaBuildPath unavailable/human off-mesh");
		} else {
			local botToHuman = false;
			local humanToBot = false;
			try {
				botToHuman = NavMesh.NavAreaBuildPath(area, humanArea, human.GetOrigin(),
					GxLdBot.Settings.ReversePathMaxLength, 2, false);
				humanToBot = NavMesh.NavAreaBuildPath(humanArea, area, bot.GetOrigin(),
					GxLdBot.Settings.ReversePathMaxLength, 2, false);
				GxLdBot.Chat(player, "5) current pair bot->human=" + botToHuman +
					" human->bot=" + humanToBot);
			} catch (epath) {
				GxLdBot.Chat(player, "5) current path pair THREW: " + epath);
			}
			if (bestUpArea != null) {
				try {
					local candidateBack = NavMesh.NavAreaBuildPath(bestUpArea, humanArea,
						human.GetOrigin(), GxLdBot.Settings.ReversePathMaxLength, 2, false);
					GxLdBot.Chat(player, "5) best up-flow candidate->human=" + candidateBack +
						" flowDelta=" + (bestUpFlow - baseFlow));
				} catch (ecandidate) {
					GxLdBot.Chat(player, "5) candidate reverse path THREW: " + ecandidate);
				}
			}
		}
	}
	GxLdBot.Chat(player, "==== end nav-probe ====");
}
