// gxLdBot squad module: spatial roles (#2), focus/attention (#3), claims (#4).
//
// What is ENACTED vs DECIDED here:
//   roles  - assignment + reason are enacted in data; team-wide spacing cvars
//            are nudged toward the squad's average follow distance. True
//            per-bot spacing needs force-button input (roadmap item).
//   focus  - target commitment + switch-cost are fully tracked and exposed as a
//            decision API (ShouldSwitchFocus). Other modules gate on it. We do
//            not force the engine's aim; we model who the bot is "paying
//            attention to" so rescue/callout timing is believable.
//   claims - fully enacted: a shared reservation table other modules honor so
//            two bots never silently chase the same medkit or downed teammate.

// ---- Roles -----------------------------------------------------------------

GxLdBot.SetTableSlot(GxLdBot, "RoleModeProfiles", {
	player = {
		point    = { followDistance = 330, leadBias = 90, label = "point" },
		flanker  = { followDistance = 285, leadBias = 82, label = "flanker" },
		follower = { followDistance = 225, leadBias = 62, label = "follower" },
		anchor   = { followDistance = 165, leadBias = 42, label = "anchor" }
	},
	escort = {
		point    = { followDistance = 250, leadBias = 78, label = "point" },
		flanker  = { followDistance = 225, leadBias = 70, label = "flanker" },
		follower = { followDistance = 185, leadBias = 56, label = "follower" },
		anchor   = { followDistance = 150, leadBias = 38, label = "anchor" }
	},
	safe = {
		point    = { followDistance = 220, leadBias = 62, label = "point" },
		flanker  = { followDistance = 200, leadBias = 58, label = "flanker" },
		follower = { followDistance = 170, leadBias = 50, label = "follower" },
		anchor   = { followDistance = 140, leadBias = 34, label = "anchor" }
	}
});

function GxLdBot::ApplyRoleMode() {
	local mode = ("Mode" in GxLdBot.Settings) ? GxLdBot.Settings.Mode : "player";
	if (!(mode in GxLdBot.RoleModeProfiles)) {
		mode = "escort";
	}
	local nextProfiles = {};
	foreach (role, rp in GxLdBot.RoleModeProfiles[mode]) {
		nextProfiles[role] <- {
			followDistance = rp.followDistance,
			leadBias = rp.leadBias,
			label = rp.label
		};
	}
	GxLdBot.SetTableSlot(GxLdBot, "RoleProfiles", nextProfiles);
}

GxLdBot.ApplyRoleMode();

// Assign one of each role across the bots (balanced squad), in entity-index
// order so it is stable within a round. Extra bots cycle the role list.
function GxLdBot::AssignRoles() {
	if (!GxLdBot.Settings.EnableRoles) {
		return;
	}
	GxLdBot.ApplyRoleMode();

	local indices = [];
	foreach (idx, p in GxLdBot.Profiles) {
		indices.append(idx);
	}
	indices.sort();
	local assigned = {};
	local used = {};
	local pickBest = function(kind) {
		local bestIdx = -1;
		local bestScore = -999999.0;
		foreach (i, idx in indices) {
			if (idx in used || !(idx in GxLdBot.Profiles)) { continue; }
			local p = GxLdBot.Profiles[idx];
			local affinity = ("leadAffinity" in p) ? p.leadAffinity : p.personalLeadBias;
			local score = 0.0;
			if (kind == "point") {
				local explore = ("StyleMemory" in GxLdBot) ? GxLdBot.StyleMemory.exploration : 0.5;
				local pace = ("StyleMemory" in GxLdBot) ? GxLdBot.StyleMemory.pace : 0.0;
				if (pace > 180.0) { pace = 180.0; }
				score = affinity + p.personalLeadBias * 0.35 +
					p.itemCuriosity * explore * 0.18 + affinity * (pace / 180.0) * 0.08;
			} else if (kind == "anchor") {
				local pressure = ("StyleMemory" in GxLdBot) ? GxLdBot.StyleMemory.pressure : 0.0;
				score = p.rescueBias + (100.0 - affinity) * 0.45 + p.composureBase * 0.2 +
					p.rescueBias * pressure * 0.12;
			} else {
				score = p.composureBase * 0.45 + p.rescueBias * 0.25 + affinity * 0.2;
			}
			if (score > bestScore) { bestScore = score; bestIdx = idx; }
		}
		if (bestIdx >= 0) { used[bestIdx] <- true; }
		return bestIdx;
	};
	local pointIdx = pickBest("point");
	local anchorIdx = pickBest("anchor");
	local flankerIdx = pickBest("flanker");
	if (pointIdx >= 0) { assigned[pointIdx] <- "point"; }
	if (anchorIdx >= 0) { assigned[anchorIdx] <- "anchor"; }
	if (flankerIdx >= 0) { assigned[flankerIdx] <- "flanker"; }
	foreach (i, idx in indices) {
		if (!(idx in assigned)) { assigned[idx] <- "follower"; }
	}

	foreach (slot, idx in indices) {
		local role = assigned[idx];
		local rp = GxLdBot.RoleProfiles[role];
		local p = GxLdBot.Profiles[idx];
		local followOffset = ("personalFollowOffset" in p) ? p.personalFollowOffset : 0;
		local personalLead = ("personalLeadBias" in p) ? p.personalLeadBias : 60;
		local lead = rp.leadBias + ((personalLead - 60) * 0.35);
		if (lead < 20) {
			lead = 20;
		}
		if (lead > 100) {
			lead = 100;
		}
		p.role = role;
		p.followDistance = rp.followDistance + followOffset;
		if (p.followDistance < 140) {
			p.followDistance = 140;
		}
		p.leadBias = lead;
		if ("ApplyCardToProfile" in GxLdBot) {
			GxLdBot.ApplyCardToProfile(idx, p);
		}
		GxLdBot.Log("role " + p.name + " role=" + role +
			" follow=" + p.followDistance + " lead=" + p.leadBias +
			" personalLead=" + personalLead +
			" identity=" + (("identityId" in p) ? p.identityId : "none") +
			" card=" + (("cardName" in p) ? p.cardName : "None"), true);
	}

	GxLdBot.FormationPlan = {};
	GxLdBot.FormationTime = -999.0;
	GxLdBot.ApplyTeamSpacing();
}

// Nudge team-wide spacing cvars toward the squad average. This is the honest
// limit of cvar control: it shifts the whole team, not individuals.
function GxLdBot::ApplyTeamSpacing() {
	if (!GxLdBot.Settings.EnableRoles || !GxLdBot.Settings.EnableMildCvars) {
		return;
	}
	local sum = 0;
	local count = 0;
	foreach (idx, p in GxLdBot.Profiles) {
		sum += p.followDistance;
		count++;
	}
	if (count <= 0) {
		return;
	}
	local avg = sum / count;
	GxLdBot.TrackedSetCvar("sb_separation_range", avg);
	GxLdBot.TrackedSetCvar("sb_separation_danger_min_range", avg + 70);
	GxLdBot.TrackedSetCvar("sb_separation_danger_max_range", avg + 240);
	GxLdBot.TrackedSetCvar("sb_neighbor_range", avg + 80);
	GxLdBot.TrackedSetCvar("sb_max_battlestation_range_from_human", GxLdBot.Settings.MaxSeparation);
	GxLdBot.TrackedSetCvar("sb_battlestation_give_up_range_from_human", GxLdBot.Settings.MaxSeparation + 80);
	GxLdBot.TrackedSetCvar("sb_enforce_proximity_range", GxLdBot.Settings.MaxSeparation + 40);
	// sb_allow_leading is handled by UpdateDynamicCvars (safe-area gated) so it
	// is NOT force-enabled here — otherwise bots lead out of the saferoom.
	GxLdBot.Log("team spacing sb_separation_range=" + avg, true);
}

function GxLdBot::PrintRoles(player) {
	local any = false;
	local plan = GxLdBot.UpdateFormationPlan(true);
	foreach (idx, p in GxLdBot.Profiles) {
		any = true;
		local slot = "none";
		if (("pointIdx" in plan) && plan.pointIdx == idx) { slot = "point"; }
		else if (("relayIdx" in plan) && plan.relayIdx == idx) { slot = "relay"; }
		else if (("rearIdx" in plan) && plan.rearIdx == idx) { slot = "rear"; }
		else if (("flexIdx" in plan) && plan.flexIdx == idx) { slot = "flex"; }
		GxLdBot.Chat(player, p.name + " role=" + p.role +
			" slot=" + slot + " follow=" + p.followDistance + " lead=" + p.leadBias +
			" card=" + (("cardName" in p) ? p.cardName : "None"));
	}
	if (!any) {
		GxLdBot.Chat(player, "no roles assigned yet");
	}
}

// ---- Buddy formation plan --------------------------------------------------
//
// Roles used to be independent personality labels, so point and flanker could
// both receive autonomous progress pressure on the same tick. The formation
// plan turns them into team slots: exactly one point leads, one relay bridges
// toward the human, one rear stays close, and an optional flex remains vanilla.

function GxLdBot::UpdateFormationPlan(force = false) {
	local now = GxLdBot.Now();
	local interval = ("FormationInterval" in GxLdBot.Settings)
		? GxLdBot.Settings.FormationInterval : 0.45;
	if (!force && (now - GxLdBot.FormationTime) < interval &&
			("pointIdx" in GxLdBot.FormationPlan)) {
		return GxLdBot.FormationPlan;
	}

	local indices = [];
	GxLdBot.ForEachSurvivorBot(function(bot) {
		if (GxLdBot.IsAlive(bot)) {
			indices.append(bot.GetEntityIndex());
		}
	});
	indices.sort();

	local used = {};
	local pickRole = function(role) {
		foreach (i, idx in indices) {
			if (idx in used || !(idx in GxLdBot.Profiles)) {
				continue;
			}
			if (GxLdBot.Profiles[idx].role == role) {
				used[idx] <- true;
				return idx;
			}
		}
		return -1;
	};
	local pickAny = function() {
		foreach (i, idx in indices) {
			if (!(idx in used)) {
				used[idx] <- true;
				return idx;
			}
		}
		return -1;
	};

	local pointIdx = pickRole("point");
	if (pointIdx < 0) { pointIdx = pickAny(); }
	local relayIdx = pickRole("flanker");
	if (relayIdx < 0) { relayIdx = pickAny(); }
	local rearIdx = pickRole("anchor");
	if (rearIdx < 0) { rearIdx = pickAny(); }
	local flexIdx = pickRole("follower");
	if (flexIdx < 0) { flexIdx = pickAny(); }

	GxLdBot.FormationPlan = {
		pointIdx = pointIdx,
		relayIdx = relayIdx,
		rearIdx = rearIdx,
		flexIdx = flexIdx,
		createdAt = now,
		expiresAt = now + interval
	};
	GxLdBot.FormationTime = now;
	return GxLdBot.FormationPlan;
}

function GxLdBot::FormationSlotFor(bot) {
	if (!GxLdBot.IsValidEntity(bot)) {
		return "none";
	}
	local plan = GxLdBot.UpdateFormationPlan(false);
	local idx = bot.GetEntityIndex();
	if (("pointIdx" in plan) && plan.pointIdx == idx) { return "point"; }
	if (("relayIdx" in plan) && plan.relayIdx == idx) { return "relay"; }
	if (("rearIdx" in plan) && plan.rearIdx == idx) { return "rear"; }
	if (("flexIdx" in plan) && plan.flexIdx == idx) { return "flex"; }
	return "none";
}

function GxLdBot::FormationEntityFor(slot) {
	local plan = GxLdBot.UpdateFormationPlan(false);
	local key = slot + "Idx";
	if (!(key in plan) || plan[key] < 0) {
		return null;
	}
	local found = null;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		if (found == null && bot.GetEntityIndex() == plan[key] && GxLdBot.IsAlive(bot)) {
			found = bot;
		}
	});
	return found;
}

function GxLdBot::SupportFlowFor(ent) {
	if (!GxLdBot.IsValidEntity(ent) || !("GetFlowFor" in GxLdBot)) {
		return null;
	}
	local now = GxLdBot.Now();
	if ((now - GxLdBot.SupportFlowCacheTime) >= GxLdBot.Settings.SupportCacheSeconds) {
		GxLdBot.SupportFlowCacheTime = now;
		GxLdBot.SupportFlowCache = {};
	}
	local idx = ent.GetEntityIndex();
	if (idx in GxLdBot.SupportFlowCache) {
		return GxLdBot.SupportFlowCache[idx];
	}
	try {
		local flow = GxLdBot.GetFlowFor(ent.GetOrigin());
		GxLdBot.SetTableSlot(GxLdBot.SupportFlowCache, idx, flow);
		return flow;
	} catch (e) {}
	return null;
}

function GxLdBot::SupportLinkPositions(posA, flowA, posB, flowB) {
	if (posA == null || posB == null) {
		return false;
	}
	local dz = posA.z - posB.z;
	if (dz < 0) { dz = -dz; }
	if (dz > GxLdBot.Settings.SupportLinkMaxZ) {
		return false;
	}
	try {
		if ((posA - posB).Length() > GxLdBot.Settings.SupportLinkDistance) {
			return false;
		}
	} catch (e) {
		return false;
	}
	if (flowA != null && flowB != null) {
		local df = flowA - flowB;
		if (df < 0) { df = -df; }
		if (df > GxLdBot.Settings.SupportLinkFlow) {
			return false;
		}
	}
	return true;
}

function GxLdBot::SupportLinkEntities(a, b) {
	if (!GxLdBot.IsValidEntity(a) || !GxLdBot.IsValidEntity(b) ||
			!GxLdBot.IsAlive(a) || !GxLdBot.IsAlive(b)) {
		return false;
	}
	try {
		return GxLdBot.SupportLinkPositions(a.GetOrigin(), GxLdBot.SupportFlowFor(a),
			b.GetOrigin(), GxLdBot.SupportFlowFor(b));
	} catch (e) {}
	return false;
}

// Survivors connected to an alive human without routing through excludedIdx.
// With four survivors this tiny fixed-point walk is cheaper and clearer than a
// general graph implementation. It is the real isolation anchor; centroid stays
// available for telemetry/rubber-band history but no longer grants permission.
function GxLdBot::HumanSupportCore(excludedIdx) {
	local now = GxLdBot.Now();
	if ((now - GxLdBot.SupportCoreCacheTime) >= GxLdBot.Settings.SupportCacheSeconds) {
		GxLdBot.SupportCoreCacheTime = now;
		GxLdBot.SupportCoreCache = {};
	}
	if (excludedIdx in GxLdBot.SupportCoreCache) {
		return GxLdBot.SupportCoreCache[excludedIdx];
	}
	local members = [];
	local connected = {};
	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s) || s.GetEntityIndex() == excludedIdx) {
			return;
		}
		members.append(s);
		if (!GxLdBot.IsBot(s)) {
			connected[s.GetEntityIndex()] <- true;
		}
	});
	if (connected.len() <= 0) {
		local empty = [];
		GxLdBot.SetTableSlot(GxLdBot.SupportCoreCache, excludedIdx, empty);
		return empty; // all-bot game: no human-anchored safety claim can be proven
	}

	local changed = true;
	while (changed) {
		changed = false;
		foreach (i, candidate in members) {
			local cidx = candidate.GetEntityIndex();
			if (cidx in connected) {
				continue;
			}
			foreach (j, anchor in members) {
				local aidx = anchor.GetEntityIndex();
				if (!(aidx in connected)) {
					continue;
				}
				if (GxLdBot.SupportLinkEntities(candidate, anchor)) {
					connected[cidx] <- true;
					changed = true;
					break;
				}
			}
		}
	}

	local out = [];
	foreach (i, s in members) {
		if (s.GetEntityIndex() in connected) {
			out.append(s);
		}
	}
	GxLdBot.SetTableSlot(GxLdBot.SupportCoreCache, excludedIdx, out);
	return out;
}

function GxLdBot::TargetHasHumanSupport(bot, pos, targetFlow) {
	if (!GxLdBot.IsValidEntity(bot) || pos == null) {
		return false;
	}
	if (!("HasAliveHuman" in GxLdBot) || !GxLdBot.HasAliveHuman()) {
		return true; // preserve all-bot test behavior; human isolation law is N/A
	}
	local core = GxLdBot.HumanSupportCore(bot.GetEntityIndex());
	foreach (i, member in core) {
		try {
			if (GxLdBot.SupportLinkPositions(pos, targetFlow, member.GetOrigin(),
					GxLdBot.SupportFlowFor(member))) {
				return true;
			}
		} catch (e) {}
	}
	return false;
}

// ---- Focus / attention -----------------------------------------------------
//
// Each bot has a current focus target and the time it committed. Switching
// targets costs time: a bot fixated on a Tank will not instantly snap to a
// Hunter that just pounced someone. This makes rescues feel earned and lets
// "missed" reactions read as plausible tunnel vision rather than a bug.

// Returns the focus record for a bot, creating a default if missing.
function GxLdBot::GetFocus(player) {
	local idx = player.GetEntityIndex();
	if (!(idx in GxLdBot.Focus)) {
		GxLdBot.Focus[idx] <- { target = null, since = GxLdBot.Now(), kind = "none" };
	}
	return GxLdBot.Focus[idx];
}

// Decision API: should `player` drop its current focus for a new target of the
// given priority (0..100)? Higher priority and longer current commitment make
// switching more likely; low-composure bots hesitate slightly more.
function GxLdBot::ShouldSwitchFocus(player, newPriority) {
	if (!GxLdBot.Settings.EnableFocus) {
		return true;
	}
	local f = GxLdBot.GetFocus(player);
	if (f.target == null || !GxLdBot.IsValidEntity(f.target)) {
		return true;
	}

	local held = GxLdBot.Now() - f.since;
	local composure = GxLdBot.CurrentComposure(player);
	// Cost shrinks as the bot has held the target longer, and as the new
	// priority climbs. Composure below 50 adds a little extra stickiness.
	local cost = GxLdBot.Settings.FocusSwitchCost;
	local hesitation = (composure < 50) ? (50 - composure) / 100.0 : 0.0;
	local threshold = cost + hesitation - (held * 0.25);
	local pull = newPriority / 50.0;

	local doSwitch = pull >= threshold;
	GxLdBot.Log("focus " + GxLdBot.SafeName(player) +
		" held=" + held + " newPri=" + newPriority +
		" pull=" + pull + " thr=" + threshold + " switch=" + doSwitch);
	return doSwitch;
}

// Commit a bot to a focus target (called by other modules when they act).
function GxLdBot::SetFocus(player, target, kind) {
	local f = GxLdBot.GetFocus(player);
	f.target = target;
	f.kind = kind;
	f.since = GxLdBot.Now();
}

function GxLdBot::PrintFocus(player) {
	local any = false;
	foreach (idx, f in GxLdBot.Focus) {
		any = true;
		local tgt = (f.target != null && GxLdBot.IsValidEntity(f.target))
			? GxLdBot.SafeName(f.target) : "none";
		GxLdBot.Chat(player, "idx=" + idx + " kind=" + f.kind +
			" target=" + tgt + " for=" + (GxLdBot.Now() - f.since) + "s");
	}
	if (!any) {
		GxLdBot.Chat(player, "no focus state yet");
	}
}

// ---- Claims / reservations -------------------------------------------------
//
// A shared table keyed by a string (e.g. "rescue:<idx>" or "item:<idx>") so
// only one bot pursues a given target/item. Claims expire so a dropped intent
// frees up for someone else.

// Try to claim `key` for `player`. Returns true if granted (free, expired, or
// already owned by this player), false if another bot holds a fresh claim.
function GxLdBot::TryClaim(key, player) {
	if (!GxLdBot.Settings.EnableClaims) {
		return true;
	}
	local now = GxLdBot.Now();
	local idx = player.GetEntityIndex();

	if (key in GxLdBot.Claims) {
		local c = GxLdBot.Claims[key];
		local fresh = (now - c.time) < GxLdBot.Settings.ClaimExpiry;
		if (fresh && c.owner != idx) {
			return false;
		}
	}

	GxLdBot.SetTableSlot(GxLdBot.Claims, key,
		{ owner = idx, time = now, name = GxLdBot.SafeName(player) });
	GxLdBot.Log("claim " + key + " -> " + GxLdBot.SafeName(player));
	return true;
}

function GxLdBot::ReleaseClaim(key, player) {
	if (key in GxLdBot.Claims && GxLdBot.Claims[key].owner == player.GetEntityIndex()) {
		delete GxLdBot.Claims[key];
	}
}

// Drop expired claims; registered as a think hook.
function GxLdBot::SweepClaims() {
	local now = GxLdBot.Now();
	local dead = [];
	foreach (key, c in GxLdBot.Claims) {
		if ((now - c.time) >= GxLdBot.Settings.ClaimExpiry) {
			dead.append(key);
		}
	}
	foreach (i, key in dead) {
		delete GxLdBot.Claims[key];
	}
}

function GxLdBot::PrintClaims(player) {
	local any = false;
	foreach (key, c in GxLdBot.Claims) {
		any = true;
		GxLdBot.Chat(player, key + " owner=" + c.name +
			" age=" + (GxLdBot.Now() - c.time) + "s");
	}
	if (!any) {
		GxLdBot.Chat(player, "no active claims");
	}
}

// ---- Scout / impatient forward pressure ------------------------------------
//
// This is the first intentionally "pushy" behavior. Point and flanker bots get
// lightweight CommandABot move orders toward positions in front of the nearest
// human. The engine still pathfinds; this only nudges intent.

function GxLdBot::IsScoutRole(profile) {
	return profile != null && (profile.role == "point" || profile.role == "flanker");
}

function GxLdBot::ScoutTargetFor(bot, human, profile) {
	if (!GxLdBot.IsValidEntity(bot) || !GxLdBot.IsValidEntity(human) || profile == null) {
		return null;
	}

	try {
		local origin = human.GetOrigin();
		local forward = human.EyeAngles().Forward();
		local ahead = GxLdBot.Settings.ScoutAheadDistance;
		local side = 0.0;

		if (profile.role == "flanker") {
			ahead = ahead * 0.82;
			side = ((bot.GetEntityIndex() % 2) == 0)
				? GxLdBot.Settings.ScoutSideOffset
				: -GxLdBot.Settings.ScoutSideOffset;
		}

		local right = Vector(-forward.y, forward.x, 0);
		return Vector(
			origin.x + (forward.x * ahead) + (right.x * side),
			origin.y + (forward.y * ahead) + (right.y * side),
			origin.z
		);
	} catch (e) {
		GxLdBot.Log("ScoutTargetFor failed: " + e, true);
		return null;
	}
}

function GxLdBot::ScoutCommonNear(ent, radius) {
	if (!GxLdBot.IsValidEntity(ent)) {
		return false;
	}

	try {
		local infected = null;
		while (infected = Entities.FindByClassnameWithin(infected, "infected",
				ent.GetOrigin(), radius)) {
			return true;
		}
	} catch (e) {
	}

	return false;
}

function GxLdBot::ScoutSpecialNear(ent, radius) {
	if (!GxLdBot.IsValidEntity(ent)) {
		return false;
	}

	try {
		local witch = Entities.FindByClassnameWithin(null, "witch", ent.GetOrigin(), radius);
		if (witch != null) {
			return true;
		}
	} catch (e) {
	}

	try {
		local p = null;
		while (p = Entities.FindByClassnameWithin(p, "player", ent.GetOrigin(), radius)) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				return true;
			}
		}
	} catch (e2) {
	}

	return false;
}

function GxLdBot::ConsiderNearestThreat(candidate, origin, best) {
	if (!GxLdBot.IsValidEntity(candidate)) {
		return best;
	}

	try {
		local d = (candidate.GetOrigin() - origin).Length();
		if (d < best.dist) {
			best.ent = candidate;
			best.dist = d;
		}
	} catch (e) {
	}

	return best;
}

function GxLdBot::NearestThreatNear(ent, commonRadius, specialRadius) {
	if (!GxLdBot.IsValidEntity(ent)) {
		return null;
	}

	local origin = ent.GetOrigin();
	local best = { ent = null, dist = 999999.0 };

	try {
		local p = null;
		while (p = Entities.FindByClassnameWithin(p, "player", origin, specialRadius)) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				best = GxLdBot.ConsiderNearestThreat(p, origin, best);
			}
		}
	} catch (e) {
	}

	try {
		local witch = null;
		while (witch = Entities.FindByClassnameWithin(witch, "witch", origin, specialRadius)) {
			best = GxLdBot.ConsiderNearestThreat(witch, origin, best);
		}
	} catch (e2) {
	}

	try {
		local infected = null;
		while (infected = Entities.FindByClassnameWithin(infected, "infected",
				origin, commonRadius)) {
			best = GxLdBot.ConsiderNearestThreat(infected, origin, best);
		}
	} catch (e3) {
	}

	return best.ent;
}

function GxLdBot::ScoutCombatNearby(bot, human) {
	local closeRadius = GxLdBot.Settings.ScoutCombatRadius;
	local specialRadius = GxLdBot.Settings.ScoutSpecialCombatRadius;

	if (GxLdBot.ScoutCommonNear(bot, closeRadius) ||
			GxLdBot.ScoutCommonNear(human, closeRadius) ||
			GxLdBot.ScoutSpecialNear(bot, specialRadius) ||
			GxLdBot.ScoutSpecialNear(human, specialRadius)) {
		GxLdBot.Log("scout paused: combat nearby");
		return true;
	}

	return false;
}

// Count same-floor commons within radius of ent (a real count, unlike
// ScoutCommonNear which stops at the first hit). Used to grade combat severity.
function GxLdBot::ScoutCommonCountNear(ent, radius) {
	if (!GxLdBot.IsValidEntity(ent)) {
		return 0;
	}
	local count = 0;
	local originZ = 0.0;
	try { originZ = ent.GetOrigin().z; } catch (e) { return 0; }
	try {
		local infected = null;
		while (infected = Entities.FindByClassnameWithin(infected, "infected",
				ent.GetOrigin(), radius)) {
			// same-floor only, reusing the Z-band that fixes multi-floor false hits
			if (!("IsSameFloor" in GxLdBot) || GxLdBot.IsSameFloor(originZ, infected)) {
				count++;
			}
		}
	} catch (e2) {
	}
	return count;
}

// Grade the combat around a scout so progress can SLOW DOWN instead of fully
// STOPPING for a couple of trash commons (player request: "zombies few → push
// faster, zombies many → slow but don't stop"). Returns:
//   0 = clear-ish (no special, commons below the slow threshold) → full speed
//   1 = light (commons crowding but no special) → advance at reduced speed
//   2 = heavy (a special/witch nearby, OR a genuine swarm) → hold, let combat run
// A special ALWAYS grades 2 (must be handled), so this never weakens the
// safety-relevant stop; it only relaxes the stop for pure trash commons.
function GxLdBot::ScoutCombatSeverity(bot, human) {
	local closeRadius = GxLdBot.Settings.ScoutCombatRadius;
	local specialRadius = GxLdBot.Settings.ScoutSpecialCombatRadius;

	// Master switch: when dynamic advance is OFF, fall back to the old binary
	// behavior — any combat nearby is a hard stop (severity 2), no slow-down tier.
	if (!GxLdBot.Settings.DynamicAdvanceEnable) {
		return GxLdBot.ScoutCombatNearby(bot, human) ? 2 : 0;
	}

	if (GxLdBot.ScoutSpecialNear(bot, specialRadius) ||
			GxLdBot.ScoutSpecialNear(human, specialRadius)) {
		return 2; // special/witch in play — always hold
	}

	local nBot = GxLdBot.ScoutCommonCountNear(bot, closeRadius);
	local nHuman = GxLdBot.IsValidEntity(human)
		? GxLdBot.ScoutCommonCountNear(human, closeRadius) : 0;
	local n = (nBot > nHuman) ? nBot : nHuman;

	local heavy = GxLdBot.Settings.DynamicHeavyCommonCount;
	local slow = GxLdBot.Settings.DynamicSlowCommonCount;
	if (n >= heavy) {
		return 2; // a real swarm — hold and clear it
	}
	if (n >= slow) {
		return 1; // crowding — slow but keep moving
	}
	return 0; // a stray common or two — full speed ahead
}

// NOTE: general combat (commons + specials that have NOT pinned anyone) is
// intentionally left to the vanilla engine AI. The old CombatNudgeTick /
// CombatTargetFor were removed in 0.3 — the only genuinely useful case,
// focus-firing a special that has pinned a teammate, is now handled by the
// rescue behavior in actions.nut. NearestThreatNear is kept (reused by retreat
// and cover positioning below / in the arbiter).

// Decision only: returns a forward scout position Vector for this bot, or null
// if it should not scout right now. The action arbiter (actions.nut) enacts the
// move, so every CommandABot call lives in one place. Reuses the gates the 0.2
// fix added: left-saferoom, per-bot start area, and yield-to-combat.
function GxLdBot::ScoutIntentFor(bot) {
	if (!GxLdBot.Settings.EnableScout) {
		return null;
	}
	if (!GxLdBot.TeamHasLeftSafeArea()) {
		return null;
	}
	if (("BotAllowsProgress" in GxLdBot) && !GxLdBot.BotAllowsProgress(bot)) {
		return null;
	}

	local profile = GxLdBot.GetProfile(bot);
	if (!GxLdBot.IsScoutRole(profile)) {
		return null;
	}
	if (GxLdBot.BotInStartArea(bot)) {
		return null;
	}

	local human = GxLdBot.NearestHuman(bot);
	if (human == null) {
		return null;
	}
	if (GxLdBot.DistanceBetween(bot, human) > GxLdBot.Settings.ScoutMaxHumanDistance) {
		return null;
	}
	if (GxLdBot.ScoutCombatNearby(bot, human)) {
		return null;
	}

	local target = GxLdBot.ScoutTargetFor(bot, human, profile);
	if (target == null) {
		return null;
	}
	try {
		if ((bot.GetOrigin() - target).Length() < GxLdBot.Settings.ScoutMinRetargetDistance) {
			return null;
		}
	} catch (e) {
	}
	return target;
}

// ---- Registration ----------------------------------------------------------
// Roles are (re)assigned by GxLdBot.EnsureProfiles whenever a bot profile is
// added (round start, late spawn, takeover, !hbot_regen), so no round hook is
// needed here.
//
// Scouting is no longer its own think hook: the single action arbiter in
// actions.nut owns every CommandABot/force decision and calls ScoutIntentFor.
// Only claim sweeping stays here.

GxLdBot.RegisterThink("sweep_claims", function() {
	GxLdBot.SweepClaims();
});
