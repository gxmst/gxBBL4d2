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

	local order = ["point", "flanker", "anchor", "follower"];
	local indices = [];
	foreach (idx, p in GxLdBot.Profiles) {
		indices.append(idx);
	}
	indices.sort();

	foreach (slot, idx in indices) {
		local role = order[slot % order.len()];
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
			" card=" + (("cardName" in p) ? p.cardName : "None"), true);
	}

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
	foreach (idx, p in GxLdBot.Profiles) {
		any = true;
		GxLdBot.Chat(player, p.name + " role=" + p.role +
			" follow=" + p.followDistance + " lead=" + p.leadBias +
			" card=" + (("cardName" in p) ? p.cardName : "None"));
	}
	if (!any) {
		GxLdBot.Chat(player, "no roles assigned yet");
	}
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
	if ("TeamUnderStress" in GxLdBot && GxLdBot.TeamUnderStress()) {
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
