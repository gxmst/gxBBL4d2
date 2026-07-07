// gxLdBot survival module: composure/stress (#5), resource style (#6).
//
// What is ENACTED vs DECIDED here:
//   composure  - fully tracked per bot from nearby special-infected threat and
//                team stress. Exposed as CurrentComposure + ReactionScale, which
//                other modules multiply into their delays. We do not override
//                engine aim; we model how rattled a bot is so timing/hesitation
//                respond to the situation like a real player choking under load.
//   resources  - heal/let-item DECISIONS are computed from personality and
//                logged with reasons. Forcing a bot to actually press heal is a
//                NetProps/force-button job (roadmap); for now this layer makes
//                the intent observable and drives heal callouts in social.nut.

// Count special infected within ThreatScanRadius of a survivor.
function GxLdBot::NearbyThreat(player) {
	local count = 0;
	local radius = GxLdBot.Settings.ThreatScanRadius;
	local classes = ["infected", "witch"];
	foreach (i, cls in classes) {
		local ent = null;
		while (ent = Entities.FindByClassnameWithin(ent, cls, player.GetOrigin(), radius)) {
			count++;
		}
	}
	// Player-class special infected (hunter/smoker/etc.) on the infected team.
	local p = null;
	while (p = Entities.FindByClassnameWithin(p, "player", player.GetOrigin(), radius)) {
		try {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				count += 2;
			}
		} catch (e) {
		}
	}
	return count;
}

// ---- Shared situation blackboard (DESIGN 3, layer 1) -----------------------
//
// THE骨架第一层: one team-wide situation, computed ONCE per arbiter tick, that
// every module reads. Before this, TeamUnderStress / HumanEmergencyVictim /
// PinnedSpecialOf were each recomputed by every bot every tick — a full survivor
// scan repeated a dozen times per 0.18s tick, which is what produced the
// SCRIPT PERF WARNING spam. Now the first caller in a tick fills the blackboard
// and everyone else reads the cache (Time() is constant within a tick).
//
// This is deliberately a passive FACT board (pinned? who's the emergency victim?
// overall situation label), NOT a behavior command. Per-bot reaction / perception
// delay (layer 2) is a later step; this step only collapses the redundant scans
// and gives one authoritative "what is happening to us" that the rest reads.

function GxLdBot::IsIncapacitatedOrHanging(player) {
	if (!GxLdBot.IsValidEntity(player) || !GxLdBot.IsAlive(player)) {
		return false;
	}
	try {
		return player.IsIncapacitated() || player.IsHangingFromLedge();
	} catch (e) {
	}
	try {
		return NetProps.GetPropInt(player, "m_isIncapacitated") != 0;
	} catch (e2) {
	}
	return false;
}

// Recompute the shared situation from scratch. One pass over all survivors:
// detects any pin (stress), the first human emergency victim (pinned or downed),
// and any bot emergency victim as a fallback. Called lazily by GetSituation.
function GxLdBot::ComputeSituation() {
	local pinned = false;
	local humanVictim = null;
	local anyVictim = null;

	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s)) {
			return;
		}
		local isPinned = false;
		foreach (i, prop in ["m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker",
				"m_carryAttacker", "m_pummelAttacker"]) {
			try {
				if (NetProps.GetPropInt(s, prop) > 0) {
					isPinned = true;
				}
			} catch (e) {
			}
		}
		if (isPinned) {
			pinned = true;
		}

		local victim = isPinned || GxLdBot.IsIncapacitatedOrHanging(s);
		if (victim) {
			if (anyVictim == null) {
				anyVictim = s;
			}
			if (humanVictim == null && !GxLdBot.IsBot(s)) {
				humanVictim = s;
			}
		}
	});

	// Situation label (DESIGN 3): a human pinned/down is the combat emergency the
	// old code reacted to; anyVictim (may be a bot) is exposed too for future use
	// but is NOT what the emergency behavior keys off (see note below).
	local label = (humanVictim != null) ? "emergency" : "clear";

	// BEHAVIOR-PRESERVING: the old HumanEmergencyVictim() returned ONLY humans, so
	// emergencyVictim stays human-only here. anyVictim is kept on the board for a
	// later step (covering a downed bot) but is intentionally not wired to
	// EmergencyDefendIntentFor yet — this step is a pure perf collapse, no手感变化.
	return {
		pinned = pinned,
		emergencyVictim = humanVictim,
		humanVictim = humanVictim,
		anyVictim = anyVictim,
		label = label,
	};
}

// Return the shared situation, recomputing at most once per tick. Time() is
// constant within a tick so we cache on the timestamp. On the rising edge into
// an emergency we stamp EmergencyOnset and clear per-bot perception delays so
// each bot re-rolls how long IT takes to notice (see PerceivesEmergency).
function GxLdBot::GetSituation() {
	local now = GxLdBot.Now();
	if ("SituationTime" in GxLdBot && GxLdBot.SituationTime == now) {
		return GxLdBot.SituationValue;
	}
	local sit = GxLdBot.ComputeSituation();

	local wasEmergency = ("EmergencyOnset" in GxLdBot) && GxLdBot.EmergencyOnset >= 0.0;
	local isEmergency = sit.emergencyVictim != null;
	if (isEmergency && !wasEmergency) {
		// Rising edge: record when the emergency began; wipe stale perception
		// stamps so each bot rolls a fresh personal delay this emergency.
		GxLdBot.SetTableSlot(GxLdBot, "EmergencyOnset", now);
		GxLdBot.SetTableSlot(GxLdBot, "PerceiveDelay", {});
	} else if (!isEmergency && wasEmergency) {
		GxLdBot.SetTableSlot(GxLdBot, "EmergencyOnset", -1.0);
	}

	GxLdBot.SetTableSlot(GxLdBot, "SituationTime", now);
	GxLdBot.SetTableSlot(GxLdBot, "SituationValue", sit);
	return sit;
}

// Perception delay (DESIGN 3 layer 2): a bot does not react to the shared
// emergency on the exact tick it starts — that "swarm mind" (all 4 snap at once)
// is the least human thing possible. Each bot rolls a small personal delay,
// scaled by its reaction personality (jumpy = short, sluggish = longer), and only
// "sees" the emergency once that delay has elapsed since onset. Kept small
// (PerceiveDelayMin..Max, ~0.1-0.5s) so it staggers reactions without ever
// endangering the victim — the delay is far shorter than any rescue traversal.
function GxLdBot::PerceivesEmergency(bot) {
	// No emergency, or the feature is off → transparent passthrough.
	if (!("EmergencyOnset" in GxLdBot) || GxLdBot.EmergencyOnset < 0.0) {
		return GxLdBot.TeamEmergency();
	}
	if (!GxLdBot.IsValidEntity(bot)) {
		return true;
	}
	if (!("PerceiveDelayMax" in GxLdBot.Settings) || GxLdBot.Settings.PerceiveDelayMax <= 0.0) {
		return true; // feature disabled by config
	}
	local idx = bot.GetEntityIndex();
	if (!("PerceiveDelay" in GxLdBot)) {
		GxLdBot.SetTableSlot(GxLdBot, "PerceiveDelay", {});
	}
	local delays = GxLdBot.PerceiveDelay;
	if (!(idx in delays)) {
		// Roll this bot's personal delay once per emergency, scaled by reaction.
		// NB: 'base' is a Squirrel reserved word (parent-class ref) — using it as a
		// local silently fails to compile the WHOLE file (DESIGN 7.3 trap), so this
		// is deliberately named baseDelay.
		local baseDelay = GxLdBot.RandFloat(GxLdBot.Settings.PerceiveDelayMin,
			GxLdBot.Settings.PerceiveDelayMax);
		local scale = 1.0;
		try { scale = GxLdBot.ReactionScale(bot); } catch (e) {}
		local d = baseDelay * scale;
		if (d > GxLdBot.Settings.PerceiveDelayMax) { d = GxLdBot.Settings.PerceiveDelayMax; }
		GxLdBot.SetTableSlot(delays, idx, d);
	}
	return (GxLdBot.Now() - GxLdBot.EmergencyOnset) >= delays[idx];
}

// Is any survivor currently pinned by a special? Now reads the blackboard.
function GxLdBot::TeamUnderStress() {
	return GxLdBot.GetSituation().pinned;
}

function GxLdBot::HumanEmergencyVictim() {
	return GxLdBot.GetSituation().emergencyVictim;
}

function GxLdBot::TeamEmergency() {
	return GxLdBot.GetSituation().emergencyVictim != null;
}

// Is the human team actively moving forward right now? True when the human
// centroid moved (past TeamMoveThreshold) within the last HumanMovingWindow
// seconds. Used to make bots PREFER walking with a moving player over stopping to
// clear stray commons (player's "when I move, move WITH me, don't peel off to
// farm zombies"). When the player stops, this goes false and assist resumes.
function GxLdBot::HumanIsMoving() {
	if (!("HumanMovingWindow" in GxLdBot.Settings)) {
		return false;
	}
	local w = GxLdBot.Settings.HumanMovingWindow;
	if (w <= 0.0) {
		return false;
	}
	return (GxLdBot.Now() - GxLdBot.LastTeamMoveTime) < w;
}

// Composure 0..100: starts from profile base, drops with nearby threat and a
// pinned teammate. Recomputed each think and stored for the decision APIs.
function GxLdBot::UpdateComposure() {
	if (!GxLdBot.Settings.EnableComposure) {
		return;
	}
	local teamStress = GxLdBot.TeamUnderStress() ? 20 : 0;

	GxLdBot.ForEachSurvivorBot(function(bot) {
		local profile = GxLdBot.GetProfile(bot);
		if (profile == null) {
			return;
		}
		local threat = GxLdBot.NearbyThreat(bot);
		local value = profile.composureBase - (threat * 6) - teamStress;
		if (value < 5) { value = 5; }
		if (value > 100) { value = 100; }
		GxLdBot.SetTableSlot(GxLdBot.Composure, bot.GetEntityIndex(), value);
	});
}

function GxLdBot::CurrentComposure(player) {
	if (!GxLdBot.Settings.EnableComposure) {
		return 100;
	}
	local idx = player.GetEntityIndex();
	if (idx in GxLdBot.Composure) {
		return GxLdBot.Composure[idx];
	}
	local profile = GxLdBot.GetProfile(player);
	return (profile != null) ? profile.composureBase : 100;
}

// Multiplier other modules apply to their reaction delays. Low composure =
// slower, more hesitant; high composure = crisp. Range roughly 0.8 .. 1.6.
function GxLdBot::ReactionScale(player) {
	local c = GxLdBot.CurrentComposure(player);
	local scale = 1.6 - (c / 125.0);
	if (scale < 0.8) { scale = 0.8; }
	if (scale > 1.6) { scale = 1.6; }
	return scale;
}

// ---- Resource style (#6) ---------------------------------------------------
//
// Personality-driven heal decision. Cautious bots (low healThreshold value =
// heals early at higher HP) vs greedy bots (heals late). Returns a decision
// table; social.nut turns a fresh "should heal" into a callout. Actually
// pressing the heal button is a roadmap item (force-button).

function GxLdBot::HealthOf(player) {
	try {
		local hp = player.GetHealth();
		local buf = 0;
		try { buf = player.GetHealthBuffer(); } catch (e) {}
		return hp + buf;
	} catch (e2) {
		return 100;
	}
}

// Does this bot have a first aid kit in the medkit slot?
// GetInvTable fills a slot->item table but CRASHES if passed a non-survivor /
// null, so we guard hard first (matching the reference mod's GetHeldItems).
function GxLdBot::HasMedkit(player) {
	if (!GxLdBot.IsSurvivor(player) || !GxLdBot.IsAlive(player)) {
		return false;
	}
	try {
		local inv = {};
		GetInvTable(player, inv);
		if ("slot3" in inv) {
			local item = inv["slot3"];
			if (item != null && GxLdBot.IsValidEntity(item)) {
				return item.GetClassname() == "weapon_first_aid_kit";
			}
		}
	} catch (e) {
		GxLdBot.Log("HasMedkit failed: " + e, true);
	}
	return false;
}

// Per-bot heal intent, recomputed each think. healThreshold (30..60) is the HP
// at which this personality wants to heal; we add a small composure wobble so
// a rattled bot may heal a touch earlier.
function GxLdBot::UpdateHealIntent() {
	if (!GxLdBot.Settings.EnableResourceStyle) {
		return;
	}
	GxLdBot.ForEachSurvivorBot(function(bot) {
		local idx = bot.GetEntityIndex();
		if (!("HealIntent" in GxLdBot)) {
			GxLdBot.HealIntent <- {};
		}

		local profile = GxLdBot.GetProfile(bot);
		if (profile == null || !GxLdBot.HasMedkit(bot)) {
			GxLdBot.SetTableSlot(GxLdBot.HealIntent, idx, false);
			return;
		}
		local hp = GxLdBot.HealthOf(bot);
		local composure = GxLdBot.CurrentComposure(bot);
		local effective = profile.healThreshold + ((composure < 40) ? 10 : 0);
		local wantsHeal = hp <= effective;

		local prev = (idx in GxLdBot.HealIntent) ? GxLdBot.HealIntent[idx] : false;
		GxLdBot.SetTableSlot(GxLdBot.HealIntent, idx, wantsHeal);

		// Only log/announce on the rising edge to avoid spam.
		if (wantsHeal && !prev) {
			GxLdBot.Log("heal_intent " + profile.name + " hp=" + hp +
				" thr=" + effective + " composure=" + composure, true);
			if ("OnHealIntent" in GxLdBot) {
				GxLdBot.OnHealIntent(bot);
			}
		}
	});
}

// Should this bot leave an item for a nearby needier human? letItemBias high =
// more generous. Used as a gate by item-pickup logic (roadmap) and exposed for
// debugging the "don't steal the human's good gun" instinct.
function GxLdBot::ShouldYieldItem(bot) {
	if (!GxLdBot.Settings.EnableResourceStyle) {
		return false;
	}
	local profile = GxLdBot.GetProfile(bot);
	if (profile == null) {
		return false;
	}
	local human = GxLdBot.NearestHuman(bot);
	if (human == null) {
		return false;
	}
	local close = GxLdBot.DistanceBetween(bot, human) < 300.0;
	local doYield = close && (profile.letItemBias >= 50);
	if (doYield) {
		GxLdBot.Log("yield_item " + profile.name + " to " + GxLdBot.SafeName(human) +
			" letBias=" + profile.letItemBias);
	}
	return doYield;
}

// ---- Retreat decision (#enacted by actions.nut arbiter) --------------------
//
// Should this bot kite back for a moment? Only when it is BOTH low on health
// AND under heavy point-blank pressure (a swarm of commons or a special right on
// it). Healthy bots stand and fight (vanilla). This is the human "back off, I'm
// getting swarmed" instinct, not a general flee.
function GxLdBot::ShouldRetreat(bot) {
	if (!GxLdBot.Settings.EnableRetreat) {
		return false;
	}
	if (!GxLdBot.IsValidEntity(bot)) {
		return false;
	}
	local profile = GxLdBot.GetProfile(bot);
	local hpThreshold = GxLdBot.Settings.RetreatHpThreshold;
	if (profile != null && "cardRetreatHpAdd" in profile) {
		hpThreshold += profile.cardRetreatHpAdd;
	}
	if (hpThreshold < 1) {
		hpThreshold = 1;
	}
	if (GxLdBot.HealthOf(bot) > hpThreshold) {
		return false;
	}

	local radius = GxLdBot.Settings.RetreatCommonRadius;
	if (profile != null && "cardRetreatRadiusAdd" in profile) {
		radius += profile.cardRetreatRadiusAdd;
	}
	if (radius < 80.0) {
		radius = 80.0;
	}
	local origin = null;
	try {
		origin = bot.GetOrigin();
	} catch (e) {
		return false;
	}

	// A special infected right on top of us is reason enough.
	try {
		local p = null;
		while (p = Entities.FindByClassnameWithin(p, "player", origin, radius)) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) {
				return true;
			}
		}
	} catch (e2) {
	}

	// Otherwise require a real swarm of commons at melee range.
	local commons = 0;
	try {
		local ent = null;
		while (ent = Entities.FindByClassnameWithin(ent, "infected", origin, radius)) {
			commons++;
		}
	} catch (e3) {
	}
	local needed = GxLdBot.Settings.RetreatCommonCount;
	if (profile != null && "cardRetreatCountAdd" in profile) {
		needed += profile.cardRetreatCountAdd;
	}
	if (needed < 1) {
		needed = 1;
	}
	return commons >= needed;
}

// ---- Registration ----------------------------------------------------------

GxLdBot.RegisterThink("composure", function() {
	GxLdBot.UpdateComposure();
});

GxLdBot.RegisterThink("heal_intent", function() {
	GxLdBot.UpdateHealIntent();
});
