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

// ---- Stable identity + conservative player-style memory --------------------

GxLdBot.SetTableSlot(GxLdBot, "IdentityTraits", {
	leader = { reactionMul = 0.88, rescueAdd = 0, composureAdd = 8,
		waitAdd = -10, interactionAdd = 4, curiosityAdd = 8, leadAffinity = 95,
		stressRiseMul = 0.90, stressDecayMul = 1.05, momentumGainMul = 1.15,
		socialGainMul = 0.95 },
	guardian = { reactionMul = 0.95, rescueAdd = 18, composureAdd = 12,
		waitAdd = 6, interactionAdd = 8, curiosityAdd = -8, leadAffinity = 42,
		stressRiseMul = 0.88, stressDecayMul = 1.12, momentumGainMul = 0.95,
		socialGainMul = 1.0 },
	curious = { reactionMul = 1.02, rescueAdd = 0, composureAdd = -2,
		waitAdd = -6, interactionAdd = 18, curiosityAdd = 24, leadAffinity = 78,
		stressRiseMul = 1.05, stressDecayMul = 1.0, momentumGainMul = 1.05,
		socialGainMul = 1.25 },
	steady = { reactionMul = 0.92, rescueAdd = 8, composureAdd = 18,
		waitAdd = 8, interactionAdd = 0, curiosityAdd = 0, leadAffinity = 58,
		stressRiseMul = 0.78, stressDecayMul = 1.2, momentumGainMul = 1.0,
		socialGainMul = 0.9 }
});

function GxLdBot::IdentityKey(player) {
	local name = GxLdBot.SafeName(player);
	try { name = name.tolower(); } catch (e) {}
	return name;
}

function GxLdBot::ApplyIdentityToProfile(player, profile) {
	local key = GxLdBot.IdentityKey(player);
	local id = (key in GxLdBot.IdentityByName) ? GxLdBot.IdentityByName[key] : null;
	if (id == null || !(id in GxLdBot.IdentityTraits)) {
		local ids = ["leader", "guardian", "curious", "steady"];
		id = ids[GxLdBot.RandInt(0, ids.len() - 1)];
		GxLdBot.SetTableSlot(GxLdBot.IdentityByName, key, id);
	}
	local trait = GxLdBot.IdentityTraits[id];
	profile.identityId <- id;
	profile.reaction = profile.reaction * trait.reactionMul;
	profile.rescueBias += trait.rescueAdd;
	profile.composureBase += trait.composureAdd;
	profile.waitBias += trait.waitAdd;
	profile.interactionBias += trait.interactionAdd;
	profile.itemCuriosity += trait.curiosityAdd;
	profile.leadAffinity <- trait.leadAffinity;
	profile.stressRiseMul <- trait.stressRiseMul;
	profile.stressDecayMul <- trait.stressDecayMul;
	profile.momentumGainMul <- trait.momentumGainMul;
	profile.socialGainMul <- trait.socialGainMul;
	if (profile.rescueBias > 100) { profile.rescueBias = 100; }
	if (profile.composureBase > 100) { profile.composureBase = 100; }
	if (profile.waitBias < 0) { profile.waitBias = 0; }
	if (profile.waitBias > 100) { profile.waitBias = 100; }
	if (profile.interactionBias < 0) { profile.interactionBias = 0; }
	if (profile.interactionBias > 100) { profile.interactionBias = 100; }
	if (profile.itemCuriosity < 0) { profile.itemCuriosity = 0; }
	if (profile.itemCuriosity > 100) { profile.itemCuriosity = 100; }
}

function GxLdBot::LoadStyleMemory() {
	if (!GxLdBot.Settings.EnableStyleMemory) { return; }
	local text = null;
	try { text = FileToString("gxldbot/style.txt"); } catch (e) { return; }
	if (text == null || text.len() <= 0) { return; }
	local lines = split(text, "\n");
	foreach (i, raw in lines) {
		local line = raw;
		try { line = strip(line); } catch (es) {}
		local at = line.find("=");
		if (at == null || at <= 0) { continue; }
		local key = line.slice(0, at);
		local value = line.slice(at + 1);
		try {
			if (key == "pace") { GxLdBot.StyleMemory.pace = value.tofloat(); }
			else if (key == "exploration") { GxLdBot.StyleMemory.exploration = value.tofloat(); }
			else if (key == "pressure") { GxLdBot.StyleMemory.pressure = value.tofloat(); }
			else if (key == "samples") { GxLdBot.StyleMemory.samples = value.tointeger(); }
			else if (key.len() > 9 && key.slice(0, 9) == "identity:") {
				GxLdBot.SetTableSlot(GxLdBot.IdentityByName, key.slice(9), value);
			}
		} catch (ep) {}
	}
}

function GxLdBot::SaveStyleMemory(reason = "periodic") {
	if (!GxLdBot.Settings.EnableStyleMemory) { return; }
	local session = GxLdBot.StyleSession;
	if (session.seconds > 3.0) {
		local sessionPace = session.distance / session.seconds;
		local oldWeight = (GxLdBot.StyleMemory.samples > 0) ? 0.78 : 0.0;
		GxLdBot.StyleMemory.pace = GxLdBot.StyleMemory.pace * oldWeight +
			sessionPace * (1.0 - oldWeight);
		local stallRate = session.stalls.tofloat() / session.seconds;
		local exploreSample = 1.0 - (stallRate * 8.0);
		if (exploreSample < 0.0) { exploreSample = 0.0; }
		if (exploreSample > 1.0) { exploreSample = 1.0; }
		GxLdBot.StyleMemory.exploration = GxLdBot.StyleMemory.exploration * 0.8 +
			exploreSample * 0.2;
		local pressureSample = session.pressure.tofloat() / session.seconds;
		if (pressureSample > 1.0) { pressureSample = 1.0; }
		GxLdBot.StyleMemory.pressure = GxLdBot.StyleMemory.pressure * 0.8 +
			pressureSample * 0.2;
		GxLdBot.StyleMemory.samples++;
	}
	local out = "pace=" + GxLdBot.StyleMemory.pace + "\n" +
		"exploration=" + GxLdBot.StyleMemory.exploration + "\n" +
		"pressure=" + GxLdBot.StyleMemory.pressure + "\n" +
		"samples=" + GxLdBot.StyleMemory.samples + "\n";
	foreach (name, id in GxLdBot.IdentityByName) {
		out += "identity:" + name + "=" + id + "\n";
	}
	try {
		StringToFile("gxldbot/style.txt", out);
		local savedAt = GxLdBot.Now();
		GxLdBot.StyleSession.lastWrite = savedAt;
		GxLdBot.StyleSession.distance = 0.0;
		GxLdBot.StyleSession.seconds = 0.0;
		GxLdBot.StyleSession.stalls = 0;
		GxLdBot.StyleSession.pressure = 0;
		GxLdBot.StyleSession.lastAt = savedAt;
		GxLdBot.Log("style memory saved reason=" + reason, true);
	} catch (e) { GxLdBot.Log("style memory save failed: " + e, true); }
}

function GxLdBot::UpdateHumanStyleSample() {
	if (!GxLdBot.Settings.EnableStyleMemory) { return; }
	local now = GxLdBot.Now();
	local origin = GxLdBot.HumanCentroid();
	if (origin == null) { return; }
	local s = GxLdBot.StyleSession;
	if (s.lastOrigin != null && s.lastAt >= 0.0 && now > s.lastAt) {
		local dt = now - s.lastAt;
		local d = 0.0;
		try { d = (origin - s.lastOrigin).Length(); } catch (e) {}
		if (d < 900.0) { s.distance += d; }
		local speed = (dt > 0.0 && d < 900.0) ? d / dt : 0.0;
		GxLdBot.HumanModel.paceEma = GxLdBot.HumanModel.paceEma * 0.78 + speed * 0.22;
		s.seconds += dt;
		if ((now - GxLdBot.LastTeamMoveTime) >= GxLdBot.Settings.StallSeconds) {
			s.stalls++;
		}
		local frame = GxLdBot.GetSituation();
		if (frame.combat || frame.emergencyVictim != null) { s.pressure++; }
	}
	s.lastOrigin = origin;
	s.lastAt = now;
	GxLdBot.HumanModel.stalledFor = now - GxLdBot.LastTeamMoveTime;
	GxLdBot.HumanModel.flow = ("HumanMaxFlow" in GxLdBot) ? GxLdBot.HumanMaxFlow() : null;
	GxLdBot.HumanModel.exploration = GxLdBot.StyleMemory.exploration;
	local point = ("FormationEntityFor" in GxLdBot) ? GxLdBot.FormationEntityFor("point") : null;
	local pointFlow = null;
	try { if (point != null) { pointFlow = GxLdBot.GetFlowFor(point.GetOrigin()); } } catch (ep) {}
	GxLdBot.HumanModel.lagging = pointFlow != null && GxLdBot.HumanModel.flow != null &&
		pointFlow > GxLdBot.HumanModel.flow + GxLdBot.Settings.SupportLinkFlow * 0.5;
}

// ---- WorldFrame -> TeamModel -> BotMind -----------------------------------

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

// Returns true when it actually rescanned this call (i.e. it burned the frame's
// heavy-work budget), false when the throttle skipped it. The caller folds that
// into the per-tick heavy-slice COUNT so a full player+witch scan and a nav
// expansion never land in the same arbiter tick.
function GxLdBot::RefreshSpecialThreats(now) {
	if ((now - GxLdBot.ThreatSampler.specialAt) < GxLdBot.Settings.ThreatSpecialInterval) { return false; }
	local specials = [];
	try {
		local p = null;
		while (p = Entities.FindByClassname(p, "player")) {
			if (NetProps.GetPropInt(p, "m_iTeamNum") == 3 && !p.IsDead()) { specials.append(p); }
		}
	} catch (especial) {}
	try {
		local witch = null;
		while (witch = Entities.FindByClassname(witch, "witch")) { specials.append(witch); }
	} catch (ewitch) {}
	GxLdBot.ThreatSampler.specials = specials;
	GxLdBot.ThreatSampler.specialAt = now;
	return true;
}

// Scan one survivor per arbiter slice. This spreads spatial-query cost across
// frames instead of running four FindByClassnameWithin loops in one lambda.
function GxLdBot::UpdateThreatSampler() {
	local now = GxLdBot.Now();
	// A special/witch refresh is itself a heavy global scan. If it ran this tick,
	// claim the per-tick heavy budget (return true) so the arbiter does NOT also
	// let a nav expansion run in the same tick — even when the cheaper common
	// slice below is not yet due. (P2#2: previously this always returned false
	// after a special refresh, leaking the "one heavy op per tick" budget.)
	local didSpecial = GxLdBot.RefreshSpecialThreats(now);
	// If the special refresh ran, it already spent this tick's heavy budget: end the
	// sampler now WITHOUT touching lastSliceAt, so the common slice runs on the next
	// arbiter tick instead of stacking a second global scan onto this one (~0.22s
	// later, no sample lost). This is what actually enforces "one heavy op per tick"
	// (P2#3): returning didSpecial while still falling through below only reported the
	// cost, it did not prevent the common scan from also running this tick.
	if (didSpecial) { return true; }
	if ((now - GxLdBot.ThreatSampler.lastSliceAt) < GxLdBot.Settings.ThreatSliceInterval) { return false; }
	local survivors = [];
	GxLdBot.ForEachSurvivor(function(s) {
		if (GxLdBot.IsAlive(s)) { survivors.append(s); }
	});
	if (survivors.len() <= 0) { return false; }
	if (GxLdBot.ThreatSampler.cursor >= survivors.len()) { GxLdBot.ThreatSampler.cursor = 0; }
	local s = survivors[GxLdBot.ThreatSampler.cursor];
	GxLdBot.ThreatSampler.cursor = (GxLdBot.ThreatSampler.cursor + 1) % survivors.len();
	GxLdBot.ThreatSampler.lastSliceAt = now;
	local origin = null;
	try { origin = s.GetOrigin(); } catch (eo) { return false; }
	local commonList = [];
	local specialList = [];
	local near430 = 0;
	try {
		local infected = null;
		while (infected = Entities.FindByClassnameWithin(infected, "infected", origin,
				GxLdBot.Settings.ThreatFrameRadius)) {
			if (!GxLdBot.IsSameFloor(origin.z, infected)) { continue; }
			local d = (infected.GetOrigin() - origin).Length();
			commonList.append({ ent = infected, dist = d });
			if (d <= 430.0) { near430++; }
		}
	} catch (ecommon) {}
	foreach (i, special in GxLdBot.ThreatSampler.specials) {
		if (!GxLdBot.IsValidEntity(special) || !GxLdBot.IsSameFloor(origin.z, special)) { continue; }
		try {
			local d = (special.GetOrigin() - origin).Length();
			if (d <= 1050.0) { specialList.append({ ent = special, dist = d }); }
		} catch (ed) {}
	}
	GxLdBot.SetTableSlot(GxLdBot.ThreatSampler.records, s.GetEntityIndex(), {
		ent = s, origin = origin, commons = commonList, specials = specialList,
		common430 = near430, updatedAt = now
	});
	return true;
}

// Recompute the shared situation from cheap survivor facts plus the incrementally
// sampled threat cache.
// detects any pin (stress), the first human emergency victim (pinned or downed),
// and any bot emergency victim as a fallback. Called lazily by GetSituation.
function GxLdBot::ComputeSituation() {
	local pinned = false;
	local humanVictim = null;
	local anyVictim = null;
	local combat = false;
	local alert = false;
	local commonEvidence = 0;
	local specialEvidence = false;
	local survivors = [];
	local threatBySurvivor = GxLdBot.ThreatSampler.records;

	// Cheap pass: survivor state only. Entity searches happen below, once per
	// WorldFrame, and their results are shared by every bot/action.
	GxLdBot.ForEachSurvivor(function(s) {
		if (!GxLdBot.IsAlive(s)) {
			return;
		}
		survivors.append(s);
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

	local now = GxLdBot.Now();
	foreach (i, s in survivors) {
		local idx = s.GetEntityIndex();
		if (!(idx in threatBySurvivor)) { continue; }
		local record = threatBySurvivor[idx];
		if ((now - record.updatedAt) > GxLdBot.Settings.ThreatRecordMaxAge) { continue; }
		local currentOrigin = null;
		try { currentOrigin = s.GetOrigin(); } catch (eo2) { continue; }
		local currentCommons = 0;
		foreach (j, item in record.commons) {
			if (!GxLdBot.IsValidEntity(item.ent)) { continue; }
			try {
				item.dist = (item.ent.GetOrigin() - currentOrigin).Length();
				if (GxLdBot.IsSameFloor(currentOrigin.z, item.ent) &&
						item.dist <= 430.0) { currentCommons++; }
			} catch (ecurrent) {}
		}
		if (currentCommons > commonEvidence) { commonEvidence = currentCommons; }
		foreach (j, item in record.specials) {
			if (!GxLdBot.IsValidEntity(item.ent)) { continue; }
			try {
				item.dist = (item.ent.GetOrigin() - currentOrigin).Length();
				if (GxLdBot.IsSameFloor(currentOrigin.z, item.ent) &&
						item.dist <= 1050.0) {
					specialEvidence = true;
					break;
				}
			} catch (especialCurrent) {}
		}
	}
	combat = specialEvidence || commonEvidence >= GxLdBot.Settings.DynamicSlowCommonCount;
	alert = !combat && commonEvidence > 0;
	return {
		pinned = pinned,
		emergencyVictim = humanVictim,
		humanVictim = humanVictim,
		anyVictim = anyVictim,
		combat = combat || pinned,
		alert = alert,
		commonEvidence = commonEvidence,
		specialEvidence = specialEvidence,
		threatBySurvivor = threatBySurvivor,
		humanMoving = GxLdBot.HumanIsMoving(),
		humanFlow = ("HumanMaxFlow" in GxLdBot) ? GxLdBot.HumanMaxFlow() : null,
		humanModel = GxLdBot.HumanModel,
		label = (humanVictim != null) ? "emergency" : (combat ? "combat" : "clear"),
	};
}

function GxLdBot::ThreatRecordFor(ent) {
	if (!GxLdBot.IsValidEntity(ent)) { return null; }
	local frame = GxLdBot.GetSituation();
	local idx = ent.GetEntityIndex();
	if (!("threatBySurvivor" in frame) || !(idx in frame.threatBySurvivor)) { return null; }
	local record = frame.threatBySurvivor[idx];
	return (GxLdBot.Now() - record.updatedAt) <= GxLdBot.Settings.ThreatRecordMaxAge
		? record : null;
}

function GxLdBot::ThreatListTarget(list, radius, required = 1) {
	if (list == null) { return null; }
	local count = 0;
	local target = null;
	local bestDist = 999999.0;
	foreach (i, item in list) {
		if (item.dist > radius) { continue; }
		if (!GxLdBot.IsValidEntity(item.ent)) { continue; }
		count++;
		if (item.dist < bestDist) { target = item.ent; bestDist = item.dist; }
	}
	return (count >= required) ? { ent = target, count = count } : null;
}

function GxLdBot::SetTeamPhase(phase, now) {
	if (GxLdBot.TeamModel.phase == phase) { return; }
	local old = GxLdBot.TeamModel.phase;
	GxLdBot.TeamModel.phase = phase;
	GxLdBot.TeamModel.since = now;
	GxLdBot.TeamModel.serial++;
	if (phase == "AFTERMATH") { GxLdBot.TeamModel.aftermathSince = now; }
	else if (phase == "SAFE") { GxLdBot.TeamModel.aftermathSince = -1.0; }
	GxLdBot.Log("team_phase " + old + " -> " + phase, true);
}

function GxLdBot::AverageMindStress() {
	local total = 0.0;
	local count = 0;
	foreach (idx, mind in GxLdBot.BotMind) { total += mind.stress; count++; }
	return (count > 0) ? total / count.tofloat() : 0.0;
}

function GxLdBot::UpdateTeamModel(frame) {
	local now = GxLdBot.Now();
	if (frame.emergencyVictim != null) {
		GxLdBot.TeamModel.lastDangerAt = now;
		GxLdBot.SetTeamPhase("EMERGENCY", now);
		return;
	}
	if (frame.combat) {
		GxLdBot.TeamModel.lastDangerAt = now;
		GxLdBot.SetTeamPhase("COMBAT", now);
		return;
	}
	if (frame.alert) {
		GxLdBot.TeamModel.lastDangerAt = now;
		GxLdBot.SetTeamPhase("ALERT", now);
		return;
	}
	local sinceDanger = now - GxLdBot.TeamModel.lastDangerAt;
	local phase = GxLdBot.TeamModel.phase;
	if ((phase == "EMERGENCY" || phase == "COMBAT" || phase == "ALERT") &&
			sinceDanger < GxLdBot.Settings.TeamAlertHold) {
		GxLdBot.SetTeamPhase("ALERT", now);
		return;
	}
	if (phase == "EMERGENCY" || phase == "COMBAT" || phase == "ALERT") {
		GxLdBot.SetTeamPhase("AFTERMATH", now);
		return;
	}
	if (phase == "AFTERMATH") {
		local held = now - GxLdBot.TeamModel.aftermathSince;
		if (held >= GxLdBot.Settings.AftermathMaxSeconds ||
				(held >= GxLdBot.Settings.AftermathMinSeconds &&
				GxLdBot.AverageMindStress() <= GxLdBot.Settings.AftermathStressExit)) {
			GxLdBot.SetTeamPhase("SAFE", now);
		}
		return;
	}
	GxLdBot.SetTeamPhase(frame.alert ? "ALERT" : "SAFE", now);
}

// Return the sampled WorldFrame and advance the shared TeamModel. BotMind keeps
// its own delayed phase snapshot; dangerous action cancellation still reads the
// objective frame immediately.
function GxLdBot::GetSituation() {
	local now = GxLdBot.Now();
	if (GxLdBot.WorldFrame != null &&
			(now - GxLdBot.WorldFrameTime) < GxLdBot.Settings.WorldFrameInterval) {
		return GxLdBot.WorldFrame;
	}
	local sit = GxLdBot.ComputeSituation();
	GxLdBot.WorldFrame = sit;
	GxLdBot.WorldFrameTime = now;
	GxLdBot.WorldSerial++;
	GxLdBot.UpdateTeamModel(sit);
	return sit;
}

function GxLdBot::GetBotMind(bot) {
	if (!GxLdBot.IsValidEntity(bot)) { return null; }
	local frame = GxLdBot.GetSituation();
	local idx = bot.GetEntityIndex();
	local now = GxLdBot.Now();
	if (!(idx in GxLdBot.BotMind)) {
		GxLdBot.BotMind[idx] <- { perceivedPhase = "SAFE", pendingPhase = "SAFE",
			noticeAt = now, seenTeamSerial = -1, stress = 0.0, momentum = 50.0,
			socialEnergy = GxLdBot.RandFloat(15.0, 55.0), updatedAt = now };
	}
	local mind = GxLdBot.BotMind[idx];
	local dt = now - mind.updatedAt;
	if (dt < 0.0) { dt = 0.0; }
	if (dt >= GxLdBot.Settings.MindUpdateInterval) {
		local profile = GxLdBot.GetProfile(bot);
		local riseMul = (profile != null && "stressRiseMul" in profile) ? profile.stressRiseMul : 1.0;
		local decayMul = (profile != null && "stressDecayMul" in profile) ? profile.stressDecayMul : 1.0;
		local momentumMul = (profile != null && "momentumGainMul" in profile) ? profile.momentumGainMul : 1.0;
		local socialMul = (profile != null && "socialGainMul" in profile) ? profile.socialGainMul : 1.0;
		if (frame.emergencyVictim != null || frame.combat) {
			mind.stress += GxLdBot.Settings.StressRisePerSecond * riseMul * dt;
			mind.momentum -= GxLdBot.Settings.MomentumLossPerSecond * dt;
		} else {
			mind.stress -= GxLdBot.Settings.StressDecayPerSecond * decayMul * dt;
			if (frame.humanMoving) {
				mind.momentum += GxLdBot.Settings.MomentumGainPerSecond * momentumMul * dt;
			}
			mind.socialEnergy += GxLdBot.Settings.ExpressionEnergyGain * socialMul * dt;
		}
		if (mind.stress < 0.0) { mind.stress = 0.0; }
		if (mind.stress > 100.0) { mind.stress = 100.0; }
		if (mind.momentum < 0.0) { mind.momentum = 0.0; }
		if (mind.momentum > 100.0) { mind.momentum = 100.0; }
		if (mind.socialEnergy > 100.0) { mind.socialEnergy = 100.0; }
		mind.updatedAt = now;
	}
	if (mind.seenTeamSerial != GxLdBot.TeamModel.serial) {
		mind.seenTeamSerial = GxLdBot.TeamModel.serial;
		mind.pendingPhase = GxLdBot.TeamModel.phase;
		local delay = GxLdBot.RandFloat(GxLdBot.Settings.PerceiveDelayMin,
			GxLdBot.Settings.PerceiveDelayMax);
		local profile = GxLdBot.GetProfile(bot);
		if (profile != null) { delay = delay * (profile.reaction / 0.4); }
		if (mind.pendingPhase == "AFTERMATH" || mind.pendingPhase == "SAFE") {
			delay += (mind.stress / 100.0) * 1.1;
		}
		if (delay < 0.05) { delay = 0.05; }
		if (mind.pendingPhase == "EMERGENCY" && delay > 0.5) { delay = 0.5; }
		mind.noticeAt = now + delay;
	}
	if (now >= mind.noticeAt) { mind.perceivedPhase = mind.pendingPhase; }
	GxLdBot.SetTableSlot(GxLdBot.Composure, idx, GxLdBot.CurrentComposure(bot));
	return mind;
}

function GxLdBot::BotPerceivedPhase(bot) {
	local mind = GxLdBot.GetBotMind(bot);
	return (mind != null) ? mind.perceivedPhase : GxLdBot.TeamModel.phase;
}

function GxLdBot::PerceivesEmergency(bot) {
	return GxLdBot.TeamEmergency() && GxLdBot.BotPerceivedPhase(bot) == "EMERGENCY";
}

function GxLdBot::BotAllowsProgress(bot) {
	local frame = GxLdBot.GetSituation();
	// HARD stops only for genuine danger: someone pinned/down, or a HEAVY threat
	// (special present, or a real common mob >= DynamicHeavyCommonCount). We do NOT
	// hard-stop on the mild `frame.combat` flag anymore: that flag flips true at just
	// DynamicSlowCommonCount (~4) commons, which in play was true >50% of the time and
	// short-circuited ProgressIntentFor entirely — bots fell back to vanilla-follow
	// (trailing the player) instead of leading. The "few zombies -> slow down but keep
	// pushing, many -> stop" decision already lives INSIDE ProgressIntentFor as the
	// severity grade (sev1 shrinks the lead, sev2 stops); letting light combat through
	// here hands that nuanced call back to the code that was built for it, instead of a
	// blunt all-or-nothing gate. (Data: sit=combat 53% of frames, act=-/- 49% — this
	// gate was the main reason the squad felt passive / glued behind the player.)
	if (frame.emergencyVictim != null || frame.pinned) { return false; }
	local heavyCount = ("DynamicHeavyCommonCount" in GxLdBot.Settings)
		? GxLdBot.Settings.DynamicHeavyCommonCount : 9;
	if (frame.specialEvidence || frame.commonEvidence >= heavyCount) { return false; }
	// Perceived-phase gate: EMERGENCY still hard-stops (per-bot delayed perception of a
	// real emergency). COMBAT no longer hard-stops here for the same reason as above —
	// it is driven by the same over-eager frame.combat flag; the severity grade inside
	// ProgressIntentFor governs how fast to push. ALERT/AFTERMATH keep advancing (damped).
	local phase = GxLdBot.BotPerceivedPhase(bot);
	return phase != "EMERGENCY";
}

function GxLdBot::BotAllowsExpression(bot) {
	local frame = GxLdBot.GetSituation();
	if (frame.emergencyVictim != null || frame.combat) { return false; }
	local mind = GxLdBot.GetBotMind(bot);
	if (mind == null) { return false; }
	if (mind.perceivedPhase == "SAFE") { return true; }
	return mind.perceivedPhase == "AFTERMATH" &&
		mind.stress <= GxLdBot.Settings.ExpressionAftermathStressMax;
}

function GxLdBot::BotAllowsAssist(bot) {
	local phase = GxLdBot.BotPerceivedPhase(bot);
	return phase == "EMERGENCY" || phase == "COMBAT";
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
	GxLdBot.ForEachSurvivorBot(function(bot) {
		GxLdBot.GetBotMind(bot);
	});
}

function GxLdBot::CurrentComposure(player) {
	if (!GxLdBot.Settings.EnableComposure) {
		return 100;
	}
	local idx = player.GetEntityIndex();
	local profile = GxLdBot.GetProfile(player);
	local value = (profile != null) ? profile.composureBase : 100.0;
	if (idx in GxLdBot.BotMind) { value -= GxLdBot.BotMind[idx].stress * 0.78; }
	if (value < 5.0) { value = 5.0; }
	if (value > 100.0) { value = 100.0; }
	return value;
}

// Multiplier other modules apply to their reaction delays. Low composure =
// slower, more hesitant; high composure = crisp. Range roughly 0.8 .. 1.6.
function GxLdBot::ReactionScale(player) {
	local c = GxLdBot.CurrentComposure(player);
	local scale = 1.6 - (c / 125.0);
	local profile = GxLdBot.GetProfile(player);
	if (profile != null) { scale = scale * (profile.reaction / 0.4); }
	if (scale < 0.8) { scale = 0.8; }
	if (scale > 2.0) { scale = 2.0; }
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

GxLdBot.RegisterThink("style_memory", function() {
	GxLdBot.UpdateHumanStyleSample();
});

GxLdBot.RegisterThink("heal_intent", function() {
	GxLdBot.UpdateHealIntent();
});
