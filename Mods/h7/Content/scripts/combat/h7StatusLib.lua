--- Heroes VII creatures and spells (heroes-memorial.h7) batch B: helpers shared by status abilities.
--- Only loaded with require("combat/h7StatusLib"), not registered as a script.
---
--- Function list (L = require("combat/h7StatusLib"))
---   Marks (hidden bonus H7_STATE_H7C, kept apart by stacking group): L.markValue / L.setMark / L.clearMark / L.removeByStacking
---   Chances: L.boost(unit) (Divination), L.roll(server, battle, unit, pct)
---   Critical hits: L.crit(server, battle, unit)
---       An H7 critical hit = a lucky strike. Combat events do not tell whether this hit was lucky (the payload has no luckyStrike),
---       so a separate roll is made from the attacker's current Luck: chance = Luck points (1-3) / 24 (as the engine's goodLuckChance / luckDiceSize), multiplied by Divination.
---       No critical hits with Luck <= 0.
---   Targets: L.canHit(battle, unit, t) (alive, not a ghost, not an arrow tower, not a war machine, not invincible, hostile)
---         L.schoolImmune(t, school) (school: earth / fire / water / air / dark / light)
---   Action tracking: L.ensureTracker(server, battle, unit) adds combat/h7StatusTick (hidden) to the battlefield once
---         L.acted(unit) already acted this round; L.turnsFor(t, n, acting) engine rounds needed to last n of its "own turns"
---   Incapacitation: L.incapacitate(server, battle, src, target, opt)
---   Damage over time: L.applyDot(server, battle, src, target, kind, first, step, left) (settled in combat/h7StatusTick)
---   Random negative spell: L.randomDebuff(server, battle, src, target)
---   Display bonuses: L.setShow(server, battle, unit, type, val, turns, stacking, extraDuration)
---   Battle log: L.log(server, battle, n, strings, numbers) (texts in the valueDescriptions of H7_STATE_H7C)

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}

M.MOD = "heroes-memorial.h7"
M.MARK = "H7_STATE_H7C"
M.TRACKER = "h7StatusTick"

local D = ENUM.BonusDuration

-- ---- Marks -------------------------------------------------------------------------------------

local function byStacking(unit, typeName, key)
	return unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == key end)
end

function M.removeByStacking(server, battle, unit, typeName, key)
	local list = byStacking(unit, typeName, key)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function M.markValue(unit, key)
	local list = byStacking(unit, M.MARK, key)
	if list:size() == 0 then return nil end
	return list:getBonus(1):getVal()
end

function M.clearMark(server, battle, unit, key)
	M.removeByStacking(server, battle, unit, M.MARK, key)
end

--- turns = nil: whole battle; otherwise N rounds (the engine counts down at the start of each round)
function M.setMark(server, battle, unit, key, val, turns)
	M.clearMark(server, battle, unit, key)
	local d = {
		type = M.MARK, val = val, hidden = true, stacking = key,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
	}
	if turns then d.duration = D.nTurns; d.turns = turns else d.duration = D.oneBattle end
	server:addUnitBonus(battle, unit, d, true)
end

-- ---- Chances -------------------------------------------------------------------------------------

function M.boost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

function M.roll(server, battle, unit, pct)
	if pct >= 100 then return true end
	if pct <= 0 then return false end
	local ok, r = pcall(function() return server:rollCombatAbility(battle, unit, pct) end)
	if ok and type(r) == "boolean" then return r end
	return server:rngInt(1, 100) <= pct
end

function M.critChance(unit)
	local luck = 0
	pcall(function() luck = unit:getLuck() end)
	if luck <= 0 then return 0 end
	if luck > 3 then luck = 3 end
	local pct = luck * 100 / 24 * (100 + M.boost(unit)) / 100
	return math.min(100, math.floor(pct + 0.5))
end

function M.crit(server, battle, unit)
	local pct = M.critChance(unit)
	if pct <= 0 then return false end
	return M.roll(server, battle, unit, pct)
end

-- ---- Targets and immunity -------------------------------------------------------------------------------

function M.canHit(battle, unit, t)
	if t == nil or not t:isAlive() or t:isGhost() or t:isTurret() or t:isInvincible() then return false end
	if not battle:isHostile(unit, t) then return false end
	if t:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return true
end

local SCHOOL = {
	earth = { "earth" }, fire = { "fire" }, water = { "water" }, air = { "air" },
	dark = { "tears-of-ashan:02darkSchool", "02darkSchool" },
	light = { "tears-of-ashan:01lightSchool", "01lightSchool" },
}

local function has(t, typeName, subtype)
	local ok, r = pcall(function() return t:hasBonuses({ type = typeName, subtype = subtype }) end)
	return ok and r == true
end

--- School immunity, negative school immunity, immunity to all negative effects
--- Plus H7 X Immunity / Magic Immunity (combat/h7Immunity, COMBAT_EVENT_TRIGGER h7SchoolImmunity with stacking h7SchoolImmunity_<school>,
--- h7MagicImmunity): blocks only that school's negative statuses (damage over time included); damage spells still hit (review R1: these were not recognized before, so Shadow Dragons still got Withering Venom)
local function h7Immune(t, school)
	local ok, list = pcall(function() return t:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }) end)
	if not ok or list == nil then return false end
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local st = b:getStacking() or ""
		local sub = tostring(b:getSubtype() or "")
		if st == "h7SchoolImmunity_" .. tostring(school) then return true end
		if sub == "h7MagicImmunity" or sub:sub(-16) == ":h7MagicImmunity" or sub:sub(-16) == ".h7MagicImmunity" then return true end
	end
	return false
end

function M.schoolImmune(t, school)
	if has(t, "NEGATIVE_EFFECTS_IMMUNITY", "any") then return true end
	for _, id in ipairs(SCHOOL[school] or {}) do
		if has(t, "SPELL_SCHOOL_IMMUNITY", id) or has(t, "NEGATIVE_EFFECTS_IMMUNITY", id) then return true end
	end
	return h7Immune(t, school)
end

function M.spellImmune(t, spell)
	return has(t, "SPELL_IMMUNITY", spell)
end

--- Two stacks adjacent (any hex touching)
function M.adjacent(a, b)
	if a:unitID() == b:unitID() then return false end
	local around = a:getSurroundingHexes()
	local hs = b:getHexes()
	for i = 1, hs:size() do
		if around:contains(hs:at(i)) then return true end
	end
	return false
end

--- units adjacent to unit that satisfy pred
function M.adjacentUnits(battle, unit, pred)
	local out = {}
	for _, o in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() end)) do
		if M.adjacent(unit, o) and (pred == nil or pred(o)) then table.insert(out, o) end
	end
	return out
end

-- ---- Action tracking ---------------------------------------------------------------------------------

function M.ensureTracker(server, battle, unit)
	if byStacking(unit, "COMBAT_EVENT_TRIGGER", M.TRACKER):size() > 0 then return end
	server:addBattleBonus(battle, {
		type = "COMBAT_EVENT_TRIGGER", subtype = M.TRACKER, val = 0, hidden = true,
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = M.TRACKER
	})
end

--- Already acted this round (waiting does not count). The mark is added by combat/h7StatusTick when the action ends and disappears automatically at the start of the next round
function M.acted(unit)
	return M.markValue(unit, "h7Acted") ~= nil
end

--- Mark of casts that do not use the turn (spells/h7abLib.markNoSkip: H7_AB_USED_H7C stacking h7NoSkipCast)
function M.noSkipCast(unit)
	return byStacking(unit, "H7_AB_USED_H7C", "h7NoSkipCast"):size() > 0
end
function M.clearNoSkipCast(server, battle, unit)
	M.removeByStacking(server, battle, unit, "H7_AB_USED_H7C", "h7NoSkipCast")
end

--- For Backstab: mark name recording "hit by which side this round"
function M.hitKey(attacker)
	if attacker:getSide() == ENUM.BattleSide.attacker then return "h7HitByA" end
	return "h7HitByD"
end

--- Lasting until the target has acted n more times: one more engine round if it has already acted (or is acting) this round
function M.turnsFor(t, n, acting)
	if acting or M.acted(t) then return n + 1 end
	return n
end

-- ---- Display bonuses -------------------------------------------------------------------------------

--- Custom bonuses for display (the type has its own icon and description; the value fills ${val}). turns = nil means the whole battle; extra is an additional end condition (added to nTurns)
function M.setShow(server, battle, unit, typeName, val, turns, key, src, extra)
	M.removeByStacking(server, battle, unit, typeName, key)
	local d = {
		type = typeName, val = val, stacking = key,
		sourceType = ENUM.BonusSource.other, sourceID = src or unit:getCreature():getJsonKey()
	}
	if turns then d.duration = D.nTurns + (extra or 0); d.turns = turns else d.duration = D.oneBattle end
	server:addUnitBonus(battle, unit, d, false)
end

-- ---- Battle log ---------------------------------------------------------------------------------

function M.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

function M.log(server, battle, n, strings, numbers)
	server:appendLog(battle, {
		append = { "core.bonus." .. M.MARK .. ".description." .. n },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

-- ---- Incapacitated (H7 Incapacitated) --------------------------------------------------------
--- The target cannot act or counterattack until the end of its next action (NOT_ACTIVE + NO_RETALIATION).
--- After it ends, it cannot be incapacitated again for 2 rounds (H7 Immune to Incapacitation).
--- opt: fragile = true ends on damage (Mesmerize, Petrification); acting = true the target is acting (an attacker hit by a counterattack);
---      showType bonus type for display; anim / sound / logN
function M.incapacitate(server, battle, src, target, opt)
	opt = opt or {}
	if not target:isAlive() or target:isGhost() or target:isInvincible() then return false end
	if M.markValue(target, "h7IncapImmune") ~= nil then return false end
	if target:hasBonuses({ type = "NOT_ACTIVE" }) then return false end

	local turns = M.turnsFor(target, 1, opt.acting)
	local extra = 0
	if opt.fragile then extra = D.untilBeingAttacked + D.untilTakingIndirectDamage end
	local key = src:getCreature():getJsonKey()
	local function add(typeName)
		server:addUnitBonus(battle, target, {
			type = typeName, val = 0, hidden = true,
			duration = D.nTurns + extra, turns = turns,
			sourceType = ENUM.BonusSource.other, sourceID = key, stacking = "h7Incap"
		}, false)
	end
	add("NOT_ACTIVE")
	add("NO_RETALIATION")
	M.setShow(server, battle, target, opt.showType or "H7_INCAP_H7C", turns, turns, "h7Incap", key, extra)
	M.setMark(server, battle, target, "h7IncapImmune", 1, turns + 2)

	server:showBattleAnimation(battle, { { unit = target } }, opt.anim or "h7/fx/h7Incap", opt.sound or "PARALYZE", 1.0, true)
	server:refreshBattleUnits(battle)
	M.log(server, battle, opt.logN or 1, { M.name(target) }, {})
	return true
end

-- ---- Damage over time ---------------------------------------------------------------------------------
--- kind: settlement and display. halve: halved each round; grow: +step each round.
--- school: school (settled with that school's immunity and damage reduction, as h7AttackLib.schoolDamage)
M.DOT = {
	acid   = { show = "H7_ACID_H7C",   mode = "halve", anim = "h7/fx/h7AcidTick",   logN = 2, school = "earth" },
	wither = { show = "H7_WITHER_H7C", mode = "halve", anim = "h7/fx/h7WitherTick", logN = 3, school = "dark" },
	venom  = { show = "H7_VENOM_H7C",  mode = "grow",  anim = "h7/fx/h7WitherTick", logN = 4, school = "dark" },
	blades = { show = "H7_BLADES_H7C", mode = "grow",  anim = "h7/fx/h7WitherTick", logN = 5, school = "dark" },
}
M.DOT_ORDER = { "acid", "wither", "venom", "blades" }

--- Hit again (refresh only, no layers): halving types keep the larger damage; growing types (Yu's decision, H7 audit C4) keep the larger current damage and the larger increment,
--- never dropping back to the starting value. Rounds always restart
function M.applyDot(server, battle, src, target, kind, first, step, left)
	local K = M.DOT[kind]
	local key = "h7Dot:" .. kind
	local oldList = byStacking(target, K.show, key)
	local oldVal = (oldList:size() > 0) and oldList:getBonus(1):getVal() or 0
	local oldStep = M.markValue(target, key .. ":step") or 0
	local val = first
	if K.mode == "halve" then
		val = math.max(first, oldVal)
	else
		val = math.max(first, oldVal)
		step = math.max(step or 0, oldStep)
	end
	M.setShow(server, battle, target, K.show, val, nil, key, src:getCreature():getJsonKey())
	M.setMark(server, battle, target, key .. ":left", left, nil)
	if K.mode == "grow" then M.setMark(server, battle, target, key .. ":step", step, nil) end
	M.ensureTracker(server, battle, src)
end

--- Settlement at round start (called by combat/h7StatusTick)
function M.tickDots(server, battle, unit)
	local BattleLog = require("battleLog")
	for _, kind in ipairs(M.DOT_ORDER) do
		if not unit:isAlive() then return end
		local K = M.DOT[kind]
		local key = "h7Dot:" .. kind
		local list = byStacking(unit, K.show, key)
		if list:size() > 0 then
			local amount = list:getBonus(1):getVal()
			local left = M.markValue(unit, key .. ":left") or 1
			local step = M.markValue(unit, key .. ":step") or 0
			-- School immunity (including H7 X Immunity / Magic Immunity) takes no damage; school damage reduction applies (review R1)
			local hurt = amount
			if K.school then
				if M.schoolImmune(unit, K.school) then hurt = 0
				else hurt = require("combat/h7AttackLib").schoolDamage(unit, amount, K.school) end
			end
			if hurt > 0 and not unit:isInvincible() then
				server:showBattleAnimation(battle, { { unit = unit } }, K.anim, "", 1.0, true)
				local dealt, killed = server:damageUnit(battle, unit, hurt)
				M.log(server, battle, K.logN, { M.name(unit) }, { dealt })
				BattleLog.creaturesPerish(server, battle, unit, killed)
			end
			left = left - 1
			local nextVal = amount
			if K.mode == "halve" then nextVal = math.max(1, math.floor(amount / 2)) else nextVal = amount + step end
			if left > 0 and unit:isAlive() then
				M.setShow(server, battle, unit, K.show, nextVal, nil, key, list:getBonus(1):getSourceID())
				M.setMark(server, battle, unit, key .. ":left", left, nil)
			else
				M.removeByStacking(server, battle, unit, K.show, key)
				M.clearMark(server, battle, unit, key .. ":left")
				M.clearMark(server, battle, unit, key .. ":step")
			end
		end
	end
end

-- ---- Random negative spells (Magic Touch, Shield of Chaos) ---------------------------------------------------------
--- H7's 7 negative statuses are replaced by original negative spells (Expert, H7 durations):
---   Dazzled (Light, Attack/Defense -4, 1 round) -> Misfortune; Burning (Fire, damage over time) -> Curse; Deep Freeze (Water, movement -3) -> Forgetfulness (shooters only);
---   Entangled (Earth, movement -2) -> Sorrow; Electrified (Air, Initiative to minimum) -> Slow; Time Control Slow -> Slow; Weakness -> Weakness
--- A new negative status first removes the one this table added before (H7 mRemoveCurrentDebuffs).
M.DEBUFFS = {
	{ spell = "misfortune",    turns = 1, anim = "C10SPF0", sound = "MISFORT" },
	{ spell = "curse",         turns = 3, anim = "C04SPW",  sound = "CURSE" },
	{ spell = "forgetfulness", turns = 3, anim = "C06SPW",  sound = "FORGET" },
	{ spell = "sorrow",        turns = 3, anim = "C14SPE0", sound = "SORROW" },
	{ spell = "slow",          turns = 3, anim = "C09SPE0", sound = "MUCKMIRE" },
	{ spell = "slow",          turns = 3, anim = "C09SPE0", sound = "MUCKMIRE" },
	{ spell = "weakness",      turns = 3, anim = "C17SPW0", sound = "WEAKNESS" },
}

local function spellObj(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(name) end)
	if s == nil then pcall(function() s = LIBRARY:getSpellByName("core:" .. name) end) end
	return s
end

local function sourceIs(b, name)
	local id = b:getSourceID() or ""
	return id == name or id == "core:" .. name
end

local function debuffList(t)
	return t:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		for _, d in ipairs(M.DEBUFFS) do
			if sourceIs(b, d.spell) then return true end
		end
		return false
	end)
end

local function plausible(t, name)
	if M.spellImmune(t, name) then return false end
	if t:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) >= 5 then return false end
	local undead = t:hasBonuses({ type = "UNDEAD" })
	local nonLiving = t:hasBonuses({ type = "NON_LIVING" }) or t:hasBonuses({ type = "MECHANICAL" })
	local mind = t:hasBonuses({ type = "MIND_IMMUNITY" })
	if name == "curse" and undead then return false end
	if name == "sorrow" and (undead or nonLiving or mind) then return false end
	if name == "forgetfulness" and (not t:isShooter() or undead or nonLiving or mind) then return false end
	return true
end

function M.randomDebuff(server, battle, src, target)
	if not M.canHit(battle, src, target) then return false end
	if M.schoolImmune(target, "none") then return false end
	local cands = {}
	for _, d in ipairs(M.DEBUFFS) do
		if plausible(target, d.spell) then table.insert(cands, d) end
	end
	if #cands == 0 then return false end
	local pick = cands[server:rngInt(1, #cands)]
	local spell = spellObj(pick.spell)
	if spell == nil then return false end

	local old = debuffList(target)
	if old:size() > 0 then server:removeUnitBonuses(battle, target, old) end
	server:applySpellEffects(battle, src, spell, { target }, 2, pick.turns, false)
	local applied = target:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		return sourceIs(b, pick.spell)
	end):size() > 0
	if not applied then return false end
	server:showBattleAnimation(battle, { { unit = target } }, pick.anim, pick.sound, 1.0, true)
	server:refreshBattleUnits(battle)
	M.log(server, battle, 6, { M.name(target), spell:getNameTextID() }, {})
	return true
end

return M
