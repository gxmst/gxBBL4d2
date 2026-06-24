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

gxldbotCardSet("CardDefs", [
	{
		id = "vanguard", name = "Vanguard", weight = 12,
		desc = "pushes map flow hard, accepts wider spacing",
		followAdd = 70, leadAdd = 22, progressLeadAdd = 260, maxSepAdd = 100,
		reactionMul = 0.92, composureAdd = 8, retreatCountAdd = 4, retreatHpAdd = -10
	},
	{
		id = "bodyguard", name = "Bodyguard", weight = 12,
		desc = "sticks near the human and clears nearby pressure",
		followAdd = -70, leadAdd = -24, progressLeadAdd = -240, maxSepAdd = -180,
		assistCountAdd = -2, assistRadiusAdd = 130, assistMaxAdd = 200,
		composureAdd = 12, retreatHpAdd = 8
	},
	{
		id = "sweeper", name = "Sweeper", weight = 14,
		desc = "turns close-horde assist on earlier and longer",
		followAdd = 20, leadAdd = 8, assistCountAdd = -3, assistRadiusAdd = 190,
		assistMaxAdd = 300, assistDurationAdd = 0.45, reactionMul = 0.82
	},
	{
		id = "berserker", name = "Berserker", weight = 10,
		desc = "fast and brave, but bad at backing off",
		followAdd = 55, leadAdd = 20, progressLeadAdd = 200, maxSepAdd = 80,
		reactionMul = 0.72, composureAdd = -8, retreatHpAdd = -18,
		retreatCountAdd = 5, assistCountAdd = -1
	},
	{
		id = "veteran", name = "Veteran", weight = 10,
		desc = "rare stable carry card",
		followAdd = 10, leadAdd = 12, progressLeadAdd = 130, reactionMul = 0.62,
		composureAdd = 28, rescueAdd = 10, assistCountAdd = -1, retreatHpAdd = -5
	},
	{
		id = "rookie", name = "Rookie", weight = 12,
		desc = "messier reactions, but still tries",
		followAdd = 40, leadAdd = -8, progressLeadAdd = -120, reactionMul = 1.35,
		composureAdd = -22, waitAdd = 18, retreatHpAdd = 15, retreatCountAdd = -2
	},
	{
		id = "skittish", name = "Skittish", weight = 10,
		desc = "stays close and retreats early",
		followAdd = -60, leadAdd = -22, progressLeadAdd = -300, maxSepAdd = -180,
		reactionMul = 1.12, composureAdd = -10, retreatHpAdd = 28,
		retreatCountAdd = -3
	},
	{
		id = "ranger", name = "Ranger", weight = 12,
		desc = "mobile flanker with moderate flow pressure",
		followAdd = 45, leadAdd = 14, progressLeadAdd = 160, maxSepAdd = 70,
		reactionMul = 0.86, assistRadiusAdd = 80, assistMaxAdd = 180
	}
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

function GxLdBot::PickCard(excludeId = null) {
	local total = 0;
	foreach (i, card in GxLdBot.CardDefs) {
		if (excludeId != null && card.id == excludeId) {
			continue;
		}
		total += ("weight" in card) ? card.weight : 1;
	}
	if (total <= 0) {
		return GxLdBot.CardDefs[0];
	}

	local roll = GxLdBot.RandInt(1, total);
	foreach (i, card in GxLdBot.CardDefs) {
		if (excludeId != null && card.id == excludeId) {
			continue;
		}
		roll -= ("weight" in card) ? card.weight : 1;
		if (roll <= 0) {
			return card;
		}
	}
	return GxLdBot.CardDefs[0];
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

function GxLdBot::AssignCard(idx, reason = "roll", excludeCurrent = false) {
	local excludeId = null;
	if (excludeCurrent && idx in GxLdBot.Cards) {
		excludeId = GxLdBot.Cards[idx].id;
	}
	local card = GxLdBot.PickCard(excludeId);
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
	GxLdBot.Notify("card:" + idx + ":" + reason, who + " " + verb +
		" card: " + card.name, (reason == "initial") ? 6.0 : 0.0);
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
		GxLdBot.Chat(player, profile.name + " card=" + cardName +
			" active=" + GxLdBot.Settings.EnableCards +
			" next=" + nextText + " " + cardDesc);
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
