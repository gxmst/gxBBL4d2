// gxLdBot cards module: roguelike-style per-bot build modifiers.
//
// Cards intentionally modify existing decision surfaces instead of issuing
// commands directly. This keeps them expressive without creating another
// command source that can fight the action arbiter.

local gxldbotCardSet = function(key, value) {
	if (key in GxLdBot) {
		GxLdBot[key] = value;
	} else {
		GxLdBot[key] <- value;
	}
};

// DESIGN 10 rogue-like rework. Cards now have a RARITY tier that drives draw
// odds (common » rare » legendary). The personalities are sharper and read as
// distinct teammates, not eight variations of one number.
//
// Fields: rarity sets weight (see CardRarityWeight below).
//   speedMul  -> movement-speed multiplier via m_flLaggedMovementValue (only bots
//                with a speed card get their prop touched; see SpeedBots).
//   signature -> short label shown in dump so a rare/legendary reads special.
// All the *Add / *Mul stat fields feed ApplyCardToProfile; the framework is
// untouched, only the DATA got richer.
gxldbotCardSet("CardRarityWeight", { common = 14, rare = 8, legendary = 5 });

gxldbotCardSet("CardDefs", [
	{
		id = "rookie", name = "Rookie", rarity = "common",
		desc = "green and jumpy: slow to react, rattles easily",
		followAdd = 30, leadAdd = -8, progressLeadAdd = -90, reactionMul = 1.45,
		composureAdd = -28, waitAdd = 20, retreatHpAdd = 15, retreatCountAdd = -2,
		signature = "",
	},
	{
		id = "steady", name = "Steady", rarity = "common",
		desc = "dependable mid-line teammate, no drama",
		followAdd = 0, leadAdd = 0, reactionMul = 0.95, composureAdd = 8,
		signature = "",
	},
	{
		id = "sweeper", name = "Sweeper", rarity = "common",
		desc = "loves clearing horde: assists earlier, wider, longer",
		followAdd = 20, leadAdd = 8, assistCountAdd = -3, assistRadiusAdd = 190,
		assistMaxAdd = 300, assistDurationAdd = 0.5, reactionMul = 0.8,
		signature = "",
	},
	{
		id = "bodyguard", name = "Bodyguard", rarity = "common",
		desc = "glued to you: protective, clears your space, revives fast",
		followAdd = -60, leadAdd = -20, progressLeadAdd = -140, maxSepAdd = -120,
		assistCountAdd = -2, assistRadiusAdd = 130, assistMaxAdd = 200,
		composureAdd = 14, rescueAdd = 16, retreatHpAdd = 8,
		signature = "",
	},
	{
		id = "triggerhappy", name = "Trigger-Happy", rarity = "common",
		desc = "twitchy spray-and-pray: snaps fast, jumpy, wastes ammo",
		followAdd = 25, leadAdd = 6, reactionMul = 0.68, composureAdd = -16,
		assistRadiusAdd = 120, assistCountAdd = -1, retreatHpAdd = 6,
		signature = "",
	},
	{
		id = "vanguard", name = "Vanguard", rarity = "rare",
		desc = "pushes the map hard, accepts wider spacing",
		followAdd = 55, leadAdd = 20, progressLeadAdd = 150, maxSepAdd = 90,
		reactionMul = 0.9, composureAdd = 10, retreatCountAdd = 4, retreatHpAdd = -10,
		signature = "",
	},
	{
		id = "ranger", name = "Ranger", rarity = "rare",
		desc = "light-footed flanker, moves a clear step quicker",
		followAdd = 35, leadAdd = 12, progressLeadAdd = 120, maxSepAdd = 60,
		reactionMul = 0.85, assistRadiusAdd = 80, assistMaxAdd = 180,
		speedMul = 1.12, signature = "fleet-footed",
	},
	{
		id = "berserker", name = "Berserker", rarity = "rare",
		desc = "fearless brawler: lightning reactions, hates backing off",
		followAdd = 40, leadAdd = 16, progressLeadAdd = 120, maxSepAdd = 80,
		reactionMul = 0.62, composureAdd = -6, retreatHpAdd = -22,
		retreatCountAdd = 6, assistCountAdd = -2,
		signature = "bloodlust",
	},
	{
		id = "guardian", name = "Guardian", rarity = "rare",
		desc = "team protector: drops everything to rescue, stays composed",
		followAdd = -30, leadAdd = -8, progressLeadAdd = -80, maxSepAdd = -60,
		reactionMul = 0.8, composureAdd = 18, rescueAdd = 30,
		assistDurationAdd = 0.4, retreatHpAdd = 4,
		signature = "guardian angel",
	},
	{
		id = "zen", name = "Zen", rarity = "rare",
		desc = "unshakeable: never panics, deliberate, patient",
		followAdd = 0, leadAdd = 4, reactionMul = 0.9, composureAdd = 32,
		waitAdd = 14, retreatHpAdd = -6,
		signature = "unshakeable",
	},
	{
		id = "veteran", name = "Veteran", rarity = "legendary",
		desc = "rock-steady carry: razor reactions, ice-cold nerves",
		followAdd = 10, leadAdd = 12, progressLeadAdd = 120, reactionMul = 0.55,
		composureAdd = 32, rescueAdd = 12, assistCountAdd = -1, retreatHpAdd = -5,
		signature = "ice in the veins",
	},
	{
		id = "sprinter", name = "Sprinter", rarity = "legendary",
		desc = "quicksilver scout: noticeably faster on foot, ranges ahead",
		followAdd = 45, leadAdd = 18, progressLeadAdd = 150, maxSepAdd = 100,
		reactionMul = 0.85, composureAdd = 6,
		speedMul = 1.28, signature = "quicksilver",
	},
	{
		id = "ace", name = "Ace", rarity = "legendary",
		desc = "the complete player: fast, calm, mobile, always there for you",
		followAdd = 15, leadAdd = 12, progressLeadAdd = 130, maxSepAdd = 60,
		reactionMul = 0.6, composureAdd = 22, rescueAdd = 14, speedMul = 1.14,
		signature = "the ace",
	},
]);

function GxLdBot::CardClamp(value, lo, hi) {
	if (value < lo) {
		return lo;
	}
	if (value > hi) {
		return hi;
	}
	return value;
}

function GxLdBot::CardValue(card, key, fallback = 0) {
	if (card != null && key in card) {
		return card[key];
	}
	return fallback;
}

function GxLdBot::CardProfileSet(profile, key, value) {
	if (key in profile) {
		profile[key] = value;
	} else {
		profile[key] <- value;
	}
}

function GxLdBot::CardById(id) {
	foreach (i, card in GxLdBot.CardDefs) {
		if (card.id == id) {
			return card;
		}
	}
	return null;
}

// Draw weight of a card: explicit weight wins (back-compat), else derived from
// rarity (common » rare » legendary) so legendaries stay a genuine surprise.
function GxLdBot::CardWeight(card) {
	if ("weight" in card) {
		return card.weight;
	}
	local r = ("rarity" in card) ? card.rarity : "common";
	if (r in GxLdBot.CardRarityWeight) {
		return GxLdBot.CardRarityWeight[r];
	}
	return 8;
}

// Weighted random draw. excludeSet is a table {id -> true} of cards NOT to draw
// (cards other bots already hold + optionally this bot's current one), so a squad
// of 4 gets 4 DISTINCT cards — no two bots share a name (10 cards >> 4 bots, so
// there is always room). If excluding everything somehow empties the pool we retry
// with no exclusions rather than返回 nothing.
function GxLdBot::PickCard(excludeSet = null) {
	local total = 0;
	foreach (i, card in GxLdBot.CardDefs) {
		if (excludeSet != null && (card.id in excludeSet)) {
			continue;
		}
		total += GxLdBot.CardWeight(card);
	}
	if (total <= 0) {
		// Everything excluded — fall back to an unconstrained draw so we never
		// return a stale/default card by accident.
		if (excludeSet != null) {
			return GxLdBot.PickCard(null);
		}
		return GxLdBot.CardDefs[0];
	}

	local roll = GxLdBot.RandInt(1, total);
	foreach (i, card in GxLdBot.CardDefs) {
		if (excludeSet != null && (card.id in excludeSet)) {
			continue;
		}
		roll -= GxLdBot.CardWeight(card);
		if (roll <= 0) {
			return card;
		}
	}
	return GxLdBot.CardDefs[0];
}

// Build the set of card ids currently held by bots OTHER than `exceptIdx`, so a
// fresh draw can avoid duplicating a teammate's card.
function GxLdBot::CardsHeldByOthers(exceptIdx) {
	local held = {};
	foreach (bidx, entry in GxLdBot.Cards) {
		if (bidx == exceptIdx) {
			continue;
		}
		if ("id" in entry) {
			held[entry.id] <- true;
		}
	}
	return held;
}

function GxLdBot::ResetCardMods(profile) {
	GxLdBot.CardProfileSet(profile, "cardId", "none");
	GxLdBot.CardProfileSet(profile, "cardName", "None");
	GxLdBot.CardProfileSet(profile, "cardDesc", "");
	GxLdBot.CardProfileSet(profile, "cardProgressLeadBonus", 0.0);
	GxLdBot.CardProfileSet(profile, "cardMaxSeparationAdd", 0.0);
	GxLdBot.CardProfileSet(profile, "cardAssistRadiusAdd", 0.0);
	GxLdBot.CardProfileSet(profile, "cardAssistCountAdd", 0);
	GxLdBot.CardProfileSet(profile, "cardAssistMaxAdd", 0.0);
	GxLdBot.CardProfileSet(profile, "cardAssistDurationAdd", 0.0);
	GxLdBot.CardProfileSet(profile, "cardRetreatHpAdd", 0);
	GxLdBot.CardProfileSet(profile, "cardRetreatRadiusAdd", 0.0);
	GxLdBot.CardProfileSet(profile, "cardRetreatCountAdd", 0);
	GxLdBot.CardProfileSet(profile, "cardRetreatDurationMul", 1.0);
}

function GxLdBot::AssignCard(idx, reason = "roll", excludeCurrent = false, forceId = null) {
	local card = null;
	if (forceId != null) {
		// Forced draw (exact card id, no randomness) — kept as a general hook.
		card = GxLdBot.CardById(forceId);
	}
	if (card == null) {
		// Avoid duplicating any card another bot already holds (distinct squad),
		// and optionally this bot's own current card on a reroll.
		local excludeSet = GxLdBot.CardsHeldByOthers(idx);
		if (excludeCurrent && idx in GxLdBot.Cards && "id" in GxLdBot.Cards[idx]) {
			excludeSet[GxLdBot.Cards[idx].id] <- true;
		}
		card = GxLdBot.PickCard(excludeSet);
	}
	local now = GxLdBot.Now();
	local entry = {
		id = card.id,
		name = card.name,
		desc = ("desc" in card) ? card.desc : "",
		since = now,
		nextRoll = now + GxLdBot.Settings.CardRerollInterval
	};
	GxLdBot.SetTableSlot(GxLdBot.Cards, idx, entry);
	GxLdBot.Log("card " + idx + " -> " + card.name + " reason=" + reason, true);
	local who = "bot#" + idx;
	if (idx in GxLdBot.Profiles && "name" in GxLdBot.Profiles[idx]) {
		who = GxLdBot.Profiles[idx].name;
	}
	local verb = (reason == "timed" || reason == "command") ? "rerolled" : "drew";
	// Rarity visual feedback (DESIGN #2): a legendary draw reads as an EVENT, not a
	// line of log. Prefix by rarity + hold the toast longer for rare/legendary so
	// pulling an Ace feels like a pull, not a stat change.
	local rarity = ("rarity" in card) ? card.rarity : "common";
	local prefix = "";
	local hold = (reason == "initial") ? 6.0 : 0.0;
	if (rarity == "legendary") {
		prefix = "*** LEGENDARY *** ";
		hold = 8.0;
	} else if (rarity == "rare") {
		prefix = "** RARE ** ";
		if (hold < 5.0) { hold = 5.0; }
	}
	local sig = ("signature" in card && card.signature != "") ? (" (" + card.signature + ")") : "";
	GxLdBot.Notify("card:" + idx + ":" + reason, prefix + who + " " + verb +
		" card: " + card.name + sig, hold);
	return card;
}

function GxLdBot::EnsureCard(idx) {
	if (!(idx in GxLdBot.Cards)) {
		return GxLdBot.AssignCard(idx, "initial", false);
	}
	local card = GxLdBot.CardById(GxLdBot.Cards[idx].id);
	if (card == null) {
		return GxLdBot.AssignCard(idx, "missing", false);
	}
	return card;
}

function GxLdBot::ApplyCardToProfile(idx, profile) {
	GxLdBot.ResetCardMods(profile);
	if (!GxLdBot.Settings.EnableCards) {
		return;
	}

	local card = GxLdBot.EnsureCard(idx);
	profile.cardId = card.id;
	profile.cardName = card.name;
	profile.cardDesc = ("desc" in card) ? card.desc : "";

	profile.followDistance = GxLdBot.CardClamp(
		profile.followDistance + GxLdBot.CardValue(card, "followAdd", 0),
		110, 420);
	profile.leadBias = GxLdBot.CardClamp(
		profile.leadBias + GxLdBot.CardValue(card, "leadAdd", 0),
		5, 100);
	profile.reaction = GxLdBot.CardClamp(
		profile.reaction * GxLdBot.CardValue(card, "reactionMul", 1.0),
		0.08, 1.6);
	profile.rescueBias = GxLdBot.CardClamp(
		profile.rescueBias + GxLdBot.CardValue(card, "rescueAdd", 0),
		5, 100);
	profile.composureBase = GxLdBot.CardClamp(
		profile.composureBase + GxLdBot.CardValue(card, "composureAdd", 0),
		10, 100);
	profile.waitBias = GxLdBot.CardClamp(
		profile.waitBias + GxLdBot.CardValue(card, "waitAdd", 0),
		0, 100);

	profile.cardProgressLeadBonus = GxLdBot.CardValue(card, "progressLeadAdd", 0).tofloat();
	profile.cardMaxSeparationAdd = GxLdBot.CardValue(card, "maxSepAdd", 0).tofloat();
	profile.cardAssistRadiusAdd = GxLdBot.CardValue(card, "assistRadiusAdd", 0).tofloat();
	profile.cardAssistCountAdd = GxLdBot.CardValue(card, "assistCountAdd", 0);
	profile.cardAssistMaxAdd = GxLdBot.CardValue(card, "assistMaxAdd", 0).tofloat();
	profile.cardAssistDurationAdd = GxLdBot.CardValue(card, "assistDurationAdd", 0).tofloat();
	profile.cardRetreatHpAdd = GxLdBot.CardValue(card, "retreatHpAdd", 0);
	profile.cardRetreatRadiusAdd = GxLdBot.CardValue(card, "retreatRadiusAdd", 0).tofloat();
	profile.cardRetreatCountAdd = GxLdBot.CardValue(card, "retreatCountAdd", 0);
	profile.cardRetreatDurationMul = GxLdBot.CardValue(card, "retreatDurationMul", 1.0).tofloat();

	// Signature ability: movespeed (some rare/legendary cards). Record the target
	// lagged-movement multiplier in the shared SpeedBots table; the cards think
	// applies it via m_flLaggedMovementValue only for flagged bots, so ordinary
	// bots keep vanilla speed (and vanilla slowdowns like spitter/tank still work).
	if (!("SpeedBots" in GxLdBot)) {
		GxLdBot.SpeedBots <- {};
	}
	local spd = (("speedMul" in card) && card.speedMul > 0) ? card.speedMul.tofloat() : 1.0;
	GxLdBot.SetTableSlot(GxLdBot.SpeedBots, idx, spd);
}

function GxLdBot::RerollAllCards(reason = "reroll") {
	GxLdBot.EnsureProfiles(false);
	GxLdBot.Cards = {};
	GxLdBot.ForEachSurvivorBot(function(bot) {
		GxLdBot.AssignCard(bot.GetEntityIndex(), reason, false);
	});
	if ("AssignRoles" in GxLdBot) {
		GxLdBot.AssignRoles();
	}
}

function GxLdBot::CardsThink() {
	if (!GxLdBot.Settings.EnableCards) {
		return;
	}
	local now = GxLdBot.Now();
	local changed = false;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		local idx = bot.GetEntityIndex();
		GxLdBot.EnsureCard(idx);
		if (!(idx in GxLdBot.Cards)) {
			return;
		}

		// Movespeed each tick = max(card speed, rubber-band speed). We only write
		// m_flLaggedMovementValue when the target differs from the current value, so
		// a bot at normal speed (no card, near the squad) is never touched and keeps
		// vanilla speed + slowdowns. Rubber-band (DESIGN 10 #1/#3): a bot far from the
		// squad centroid speeds up to rejoin instead of trailing and getting swarmed.
		local target = 1.0;
		if ("SpeedBots" in GxLdBot && idx in GxLdBot.SpeedBots) {
			target = GxLdBot.SpeedBots[idx];
		}
		if (("RubberBandEnable" in GxLdBot.Settings) && GxLdBot.Settings.RubberBandEnable &&
				("BotCentroidDispersion" in GxLdBot)) {
			local d = GxLdBot.BotCentroidDispersion(bot);
			local nearD = GxLdBot.Settings.RubberBandNearDist;
			local farD = GxLdBot.Settings.RubberBandFarDist;
			if (d > nearD && farD > nearD) {
				local t = (d - nearD) / (farD - nearD);
				if (t > 1.0) { t = 1.0; }
				local rb = 1.0 + t * (GxLdBot.Settings.RubberBandMaxSpeed - 1.0);
				if (rb > target) { target = rb; }
			}
		}
		try {
			local cur = NetProps.GetPropFloat(bot, "m_flLaggedMovementValue");
			if (cur < target - 0.01 || cur > target + 0.01) {
				NetProps.SetPropFloat(bot, "m_flLaggedMovementValue", target);
			}
		} catch (e) {}

		local entry = GxLdBot.Cards[idx];
		if (!("nextRoll" in entry) || now < entry.nextRoll) {
			return;
		}
		entry.nextRoll = now + GxLdBot.Settings.CardRerollInterval;
		if (GxLdBot.RandInt(1, 100) <= GxLdBot.Settings.CardRerollChance) {
			GxLdBot.AssignCard(idx, "timed", true);
			changed = true;
		}
	});
	if (changed && "AssignRoles" in GxLdBot) {
		GxLdBot.AssignRoles();
	}
}

function GxLdBot::PrintCards(player) {
	local any = false;
	GxLdBot.ForEachSurvivorBot(function(bot) {
		any = true;
		local idx = bot.GetEntityIndex();
		local profile = GxLdBot.GetProfile(bot);
		if (profile == null) {
			return;
		}
		local card = GxLdBot.EnsureCard(idx);
		local nextText = "off";
		if (idx in GxLdBot.Cards && "nextRoll" in GxLdBot.Cards[idx]) {
			local remain = GxLdBot.Cards[idx].nextRoll - GxLdBot.Now();
			if (remain < 0) {
				remain = 0;
			}
			nextText = remain.tointeger() + "s";
		}
		local cardName = (card != null) ? card.name : "None";
		local cardDesc = (card != null && "desc" in card) ? card.desc : "";
		local rarity = (card != null && "rarity" in card) ? card.rarity : "common";
		local sig = (card != null && "signature" in card) ? (" *" + card.signature + "*") : "";
		GxLdBot.Chat(player, profile.name + " [" + rarity + "] card=" + cardName +
			sig + " next=" + nextText + " " + cardDesc);
	});
	if (!any) {
		GxLdBot.Chat(player, "no survivor bots");
	}
	if (!GxLdBot.Settings.EnableCards) {
		GxLdBot.Chat(player, "cards are OFF (!hbot_cards_toggle to enable)");
	}
}

GxLdBot.RegisterThink("cards", function() {
	GxLdBot.CardsThink();
});
