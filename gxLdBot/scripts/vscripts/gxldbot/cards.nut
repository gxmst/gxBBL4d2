// gxLdBot cards module: chapter-scoped build modifiers over stable identities.
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
// Fields: rarity sets weight (see CardRarityWeight below). Curve modifiers tune
// stress recovery, momentum and expression energy; cards never write movement
// NetProps. signature is the short label shown in the dump.
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
		desc = "mobile flanker: builds momentum quickly and checks side routes",
		followAdd = 35, leadAdd = 12, progressLeadAdd = 120, maxSepAdd = 60,
		reactionMul = 0.85, assistRadiusAdd = 80, assistMaxAdd = 180,
		momentumGainMul = 1.25, interactionAdd = 8, signature = "trail sense",
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
		desc = "quicksilver scout: recovers initiative fast and ranges ahead",
		followAdd = 45, leadAdd = 18, progressLeadAdd = 150, maxSepAdd = 100,
		reactionMul = 0.85, composureAdd = 6,
		momentumGainMul = 1.45, stressDecayMul = 1.2, signature = "quicksilver",
	},
	{
		id = "ace", name = "Ace", rarity = "legendary",
		desc = "the complete player: calm, decisive, social, always there for you",
		followAdd = 15, leadAdd = 12, progressLeadAdd = 130, maxSepAdd = 60,
		reactionMul = 0.6, composureAdd = 22, rescueAdd = 14,
		momentumGainMul = 1.2, socialGainMul = 1.2, interactionAdd = 12,
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

function GxLdBot::CurrentChapterName() {
	try { return Director.GetMapName(); } catch (e) {}
	try { return GetMapName(); } catch (e2) {}
	return "unknown";
}

function GxLdBot::PrepareBuildCardsForChapter() {
	local chapter = GxLdBot.CurrentChapterName();
	if (GxLdBot.BuildCardChapter == "") {
		GxLdBot.BuildCardChapter = chapter;
		return;
	}
	if (chapter != "unknown" && chapter != GxLdBot.BuildCardChapter) {
		GxLdBot.BuildCardsByName = {};
		GxLdBot.BuildCardChapter = chapter;
		GxLdBot.Log("new chapter build draw: " + chapter, true);
	}
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
	GxLdBot.CardProfileSet(profile, "cardStressRiseMul", 1.0);
	GxLdBot.CardProfileSet(profile, "cardStressDecayMul", 1.0);
	GxLdBot.CardProfileSet(profile, "cardMomentumGainMul", 1.0);
	GxLdBot.CardProfileSet(profile, "cardSocialGainMul", 1.0);
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
		nextRoll = -1.0
	};
	GxLdBot.SetTableSlot(GxLdBot.Cards, idx, entry);
	if (idx in GxLdBot.Profiles) {
		local buildKey = GxLdBot.Profiles[idx].name.tolower();
		GxLdBot.SetTableSlot(GxLdBot.BuildCardsByName, buildKey, card.id);
	}
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
		if (idx in GxLdBot.Profiles) {
			local buildKey = GxLdBot.Profiles[idx].name.tolower();
			if (buildKey in GxLdBot.BuildCardsByName) {
				return GxLdBot.AssignCard(idx, "chapter_restore", false,
					GxLdBot.BuildCardsByName[buildKey]);
			}
		}
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
	// Rebase identity/personality values before applying a chapter build so role
	// reassignment or debug regeneration never compounds card modifiers.
	if ("baseReaction" in profile) { profile.reaction = profile.baseReaction; }
	if ("baseRescueBias" in profile) { profile.rescueBias = profile.baseRescueBias; }
	if ("baseComposure" in profile) { profile.composureBase = profile.baseComposure; }
	if ("baseWaitBias" in profile) { profile.waitBias = profile.baseWaitBias; }
	if ("baseInteractionBias" in profile) { profile.interactionBias = profile.baseInteractionBias; }
	if ("baseItemCuriosity" in profile) { profile.itemCuriosity = profile.baseItemCuriosity; }
	if ("baseStressRiseMul" in profile) { profile.stressRiseMul = profile.baseStressRiseMul; }
	if ("baseStressDecayMul" in profile) { profile.stressDecayMul = profile.baseStressDecayMul; }
	if ("baseMomentumGainMul" in profile) { profile.momentumGainMul = profile.baseMomentumGainMul; }
	if ("baseSocialGainMul" in profile) { profile.socialGainMul = profile.baseSocialGainMul; }
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
	profile.interactionBias = GxLdBot.CardClamp(
		profile.interactionBias + GxLdBot.CardValue(card, "interactionAdd", 0), 0, 100);
	profile.itemCuriosity = GxLdBot.CardClamp(
		profile.itemCuriosity + GxLdBot.CardValue(card, "curiosityAdd", 0), 0, 100);

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
	profile.cardStressRiseMul = GxLdBot.CardValue(card, "stressRiseMul", 1.0).tofloat();
	profile.cardStressDecayMul = GxLdBot.CardValue(card, "stressDecayMul", 1.0).tofloat();
	profile.cardMomentumGainMul = GxLdBot.CardValue(card, "momentumGainMul", 1.0).tofloat();
	profile.cardSocialGainMul = GxLdBot.CardValue(card, "socialGainMul", 1.0).tofloat();
	if ("stressRiseMul" in profile) { profile.stressRiseMul *= profile.cardStressRiseMul; }
	if ("stressDecayMul" in profile) { profile.stressDecayMul *= profile.cardStressDecayMul; }
	if ("momentumGainMul" in profile) { profile.momentumGainMul *= profile.cardMomentumGainMul; }
	if ("socialGainMul" in profile) { profile.socialGainMul *= profile.cardSocialGainMul; }
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
	// Rubber-band is a movement actuator, not a card stat. Keep it in this existing
	// low-frequency pass for cost control, but route every write through the shared
	// lease driver in actions.nut.
	if (("LeaseMovementBoost" in GxLdBot) && ("ReleaseMovementBoost" in GxLdBot)) {
		GxLdBot.ForEachSurvivorBot(function(bot) {
			local shouldBoost = GxLdBot.Settings.RubberBandEnable &&
				GxLdBot.Settings.EnableActions && GxLdBot.IsAlive(bot) &&
				(!("IsUncommandable" in GxLdBot) || !GxLdBot.IsUncommandable(bot));
			if (!shouldBoost || !("BotCentroidDispersion" in GxLdBot)) {
				GxLdBot.ReleaseMovementBoost(bot, "rubberband_inactive");
				return;
			}

			// Do not accelerate a forward point/relay. With usable flow, boost only a
			// bot genuinely behind the human; on flat-flow maps, reserve it for rear/flex.
			local behind = true;
			if (("HumanMaxFlow" in GxLdBot) && ("GetFlowFor" in GxLdBot)) {
				local humanFlow = GxLdBot.HumanMaxFlow();
				local botFlow = null;
				try { botFlow = GxLdBot.GetFlowFor(bot.GetOrigin()); } catch (eflow) {}
				if (humanFlow != null && botFlow != null) {
					behind = botFlow + GxLdBot.Settings.ProgressFlowTolerance < humanFlow;
				} else if (("FormationSlotFor" in GxLdBot)) {
					local slot = GxLdBot.FormationSlotFor(bot);
					behind = slot != "point" && slot != "relay";
				}
			}
			if (!behind) {
				GxLdBot.ReleaseMovementBoost(bot, "rubberband_not_behind");
				return;
			}

			// Boost strength = MAX of two drivers:
			//   (a) centroid dispersion — the old "bot strayed from the squad" signal.
			//   (b) FLOW deficit behind the human — the fix for "player rushes ahead
			//       solo". When you sprint out front, the two other bots stay clustered
			//       so the straggler's dispersion from THEIR centroid stays small and (a)
			//       never fires — yet it is hundreds of flow behind YOU. Data: bots sat
			//       avg -509 flow behind an aggressive player while stuck on vanilla/
			//       escort follow. Driving the boost off "how far behind the human in
			//       flow" makes a trailing bot genuinely sprint to catch up and keep the
			//       pace of a fast human, instead of ambling along one boost tier down.
			local nearD = GxLdBot.Settings.RubberBandNearDist;
			local farD = GxLdBot.Settings.RubberBandFarDist;
			local t = 0.0;
			if (farD > nearD) {
				local d = GxLdBot.BotCentroidDispersion(bot);
				if (d > nearD) {
					local td = (d - nearD) / (farD - nearD);
					if (td > t) { t = td; }
				}
			}
			// (b) flow-deficit driver: how far behind the human this bot is, in flow.
			if (("HumanMaxFlow" in GxLdBot) && ("GetFlowFor" in GxLdBot)) {
				local hf = GxLdBot.HumanMaxFlow();
				local bfv = null;
				try { bfv = GxLdBot.GetFlowFor(bot.GetOrigin()); } catch (efb) {}
				if (hf != null && bfv != null) {
					local deficit = hf - bfv;
					local nearF = ("RubberBandFlowNear" in GxLdBot.Settings)
						? GxLdBot.Settings.RubberBandFlowNear : 350.0;
					local farF = ("RubberBandFlowFar" in GxLdBot.Settings)
						? GxLdBot.Settings.RubberBandFlowFar : 1200.0;
					if (deficit > nearF && farF > nearF) {
						local tf = (deficit - nearF) / (farF - nearF);
						if (tf > t) { t = tf; }
					}
				}
			}
			if (t <= 0.0) {
				GxLdBot.ReleaseMovementBoost(bot, "rubberband_rejoined");
				return;
			}
			if (t > 1.0) { t = 1.0; }
			local target = 1.0 + t * (GxLdBot.Settings.RubberBandMaxSpeed - 1.0);
			if (target > 1.0) { GxLdBot.LeaseMovementBoost(bot, target); }
		});
	} else if (("ReleaseAllMovementBoosts" in GxLdBot)) {
		GxLdBot.ReleaseAllMovementBoosts("rubberband_driver_missing");
	}

	if (!GxLdBot.Settings.EnableCards) {
		return;
	}
	GxLdBot.ForEachSurvivorBot(function(bot) {
		local idx = bot.GetEntityIndex();
		GxLdBot.EnsureCard(idx);
	});
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
		local nextText = "next chapter";
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
