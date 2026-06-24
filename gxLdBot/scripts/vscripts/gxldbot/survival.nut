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

// Is any survivor currently pinned by a special? Raises team stress.
function GxLdBot::TeamUnderStress() {
	local pinned = false;
	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s)) {
			return;
		}
		foreach (i, prop in ["m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker",
				"m_carryAttacker", "m_pummelAttacker"]) {
			try {
				if (NetProps.GetPropInt(s, prop) > 0) {
					pinned = true;
				}
			} catch (e) {
			}
		}
	});
	return pinned;
}

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

function GxLdBot::HumanEmergencyVictim() {
	local best = null;
	GxLdBot.ForEachSurvivor(function(s) {
		if (best != null || GxLdBot.IsBot(s) || !GxLdBot.IsAlive(s)) {
			return;
		}
		if (("PinnedSpecialOf" in GxLdBot) && GxLdBot.PinnedSpecialOf(s) != null) {
			best = s;
			return;
		}
		if (GxLdBot.IsIncapacitatedOrHanging(s)) {
			best = s;
		}
	});
	return best;
}

function GxLdBot::TeamEmergency() {
	return GxLdBot.HumanEmergencyVictim() != null;
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
