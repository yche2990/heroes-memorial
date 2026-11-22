--- Heroes VII creatures and spells (heroes-memorial.h7): helpers shared by creature active abilities (batch E).
--- Only loaded with require("spells/h7abLib"), not registered as a script.
---
---   L.MARK                                 bonus type of the counting mark (hidden), stacking = the ability's key
---   L.LOG                                  hidden bonus type for the battle log (valueDescriptions 1-N)
---   L.hexIndex / hexTable / hexDistance / unitDistance / unitHexDistance
---   L.neighbours(hex)                      the six adjacent hexes (valid ones only)
---   L.adjacent(a, b)                       whether two stacks are adjacent
---   L.enemyAdjacent(battle, unit)          whether a living enemy is adjacent (a blocked shooter cannot shoot)
---   L.isEnemyOf(a, b) / L.real(u)          friend or foe (by getSide) / real stack (alive, present, not an arrow tower, not a war machine)
---   L.name(unit)                           name for the battle log
---   L.log(server, battle, index, strings, numbers)
---   L.markVal(unit, key) / setMark / clearMark
---   L.refundCast(server, battle, caster)   refund this cast (CASTS +1, whole battle): batch E abilities are limited by marks and do not use the shared casts
---   L.removeByStacking(server, battle, unit, type, stacking)
---   L.addBonus(server, battle, unit, desc)  creature ability source; desc.duration / valueType may be given by name ("nTurns", {"untilAfterAttackSequence","nTurns"})
---   L.freeHexNextTo(battle, unit, target, from)  free hex next to target where unit fits, nearest to from
---   L.nearestFree(battle, unit, hex)       hex nearest to hex where unit fits (may be hex itself)
---   L.reviveHeal(unit, amount)             becomes normal healing with the Ring of Oblivion in play (as hota ringOfOblivionPatch.lua)
---   L.rollDamage(server, attacker, target, attackBonus, pct, ranged)  estimate one attack's damage with the H3 formula (when Lua settles damage itself)

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local L = {}
L.MOD = "heroes-memorial.h7"
L.MARK = "H7_AB_USED_H7C"
L.LOG = "H7_ABE_LOG_H7C"

local W = 17

function L.hexIndex(hex)
	return hex:getX() + hex:getY() * W
end

function L.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[L.hexIndex(h)] = h
	end
	return t
end

function L.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function L.unitDistance(a, b)
	local ha, hb = a:getHexes(), b:getHexes()
	local best = 1000
	for i = 1, ha:size() do
		for j = 1, hb:size() do
			local d = L.hexDistance(ha:at(i), hb:at(j))
			if d < best then best = d end
		end
	end
	return best
end

function L.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do
		local d = L.hexDistance(hs:at(i), hex)
		if d < best then best = d end
	end
	return best
end

local DIRS = { "copyToEast", "copyToWest", "copyToNorthEast", "copyToNorthWest", "copyToSouthEast", "copyToSouthWest" }
L.DIRS = DIRS

function L.neighbours(hex)
	local out = {}
	for _, d in ipairs(DIRS) do
		local ok, h = pcall(function() return hex[d](hex) end)
		if ok and h ~= nil and h:isValid() then out[#out + 1] = h end
	end
	return out
end

function L.adjacent(a, b)
	return L.unitDistance(a, b) <= 1
end

function L.isEnemyOf(a, b)
	return a:getSide() ~= b:getSide()
end

function L.real(u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return true
end

function L.enemyAdjacent(battle, unit)
	local side = unit:getSide()
	local list = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret()
	end)
	for _, u in ipairs(list) do
		if L.adjacent(unit, u) then return true end
	end
	return false
end

function L.name(unit)
	return unit:getCreature():getNameTextID(unit:getCount())
end

function L.log(server, battle, index, strings, numbers)
	server:appendLog(battle, {
		append         = { "core.bonus." .. L.LOG .. ".description." .. tostring(index) },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

function L.removeByStacking(server, battle, unit, typeName, stacking)
	local list = unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == stacking end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function L.markVal(unit, key)
	local list = unit:getBonuses({ type = L.MARK })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if b:getStacking() == key then return b:getVal() end
	end
	return nil
end

function L.clearMark(server, battle, unit, key)
	L.removeByStacking(server, battle, unit, L.MARK, key)
end

function L.setMark(server, battle, unit, key, val)
	L.clearMark(server, battle, unit, key)
	server:addUnitBonus(battle, unit, {
		type       = L.MARK,
		val        = val,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		stacking   = key,
		hidden     = true
	}, true)
end

--- H7 audit (Yu's decision 2a): "once per battle" preparation abilities get the use refunded when the preparation goes unused (removed because an enemy attacked first, or expired at the end of the round).
--- When preparing, h7ArmPending is recorded on the stack (value = index in the table below); cleared on its own attack (combat/h7StatusTick), refunded when removed / expired.
L.ARM_TYPES = { "H7_LEAF_ARMED_H7C", "H7_IMPLODE_ARMED_H7C", "H7_STING_ARMED_H7C" }
L.ARM_USES = { H7_LEAF_ARMED_H7C = "h7AbLeafDaggers", H7_IMPLODE_ARMED_H7C = "h7AbImplodingArrow", H7_STING_ARMED_H7C = "h7AbCripplingSting" }
L.ARM_PENDING = "h7ArmPending"

function L.armPending(server, battle, unit, mark)
	for i, t in ipairs(L.ARM_TYPES) do
		if t == mark then L.setMark(server, battle, unit, L.ARM_PENDING, i) return end
	end
end

--- Preparation used (it attacked on its own)
function L.armConsumed(server, battle, unit)
	if L.markVal(unit, L.ARM_PENDING) ~= nil then L.clearMark(server, battle, unit, L.ARM_PENDING) end
end

--- Preparation unused: refund this use; with onlyIfGone = true only if the prepared mark is no longer on it (used for the expiry check at round start)
function L.armRefund(server, battle, unit, onlyIfGone)
	local idx = L.markVal(unit, L.ARM_PENDING)
	if idx == nil then return false end
	local mark = L.ARM_TYPES[idx]
	if mark == nil then L.clearMark(server, battle, unit, L.ARM_PENDING) return false end
	if onlyIfGone then
		local ok, has = pcall(function() return unit:hasBonuses({ type = mark }) end)
		if ok and has then return false end
	end
	L.clearMark(server, battle, unit, L.ARM_PENDING)
	local key = L.ARM_USES[mark]
	local used = key and L.markVal(unit, key) or nil
	if used == nil then return false end
	if used <= 1 then L.clearMark(server, battle, unit, key) else L.setMark(server, battle, unit, key, used - 1) end
	return true
end

--- Mark of "casts that do not use the turn" (preparation / charge abilities, canCastWithoutSkip): stacking h7NoSkipCast, valid this round.
--- It records that "this action is a cast that does not end the turn"; Victorious Streak, action tracking (h7StatusTick) and effects lasting until the end of the next action (AttackLib.ownTurnEnded)
--- treat the cast like a wait when they see it in onUnitSpellcast (not a full action), and remove it in onActionFinished.
L.NOSKIP = "h7NoSkipCast"
function L.markNoSkip(server, battle, caster)
	L.removeByStacking(server, battle, caster, L.MARK, L.NOSKIP)
	server:addUnitBonus(battle, caster, {
		type       = L.MARK,
		val        = 1,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = caster:getCreature():getJsonKey(),
		stacking   = L.NOSKIP,
		hidden     = true
	}, true)
end

--- Add combat/h7StatusTick to the battlefield once (as combat/h7StatusLib.ensureTracker): the prepared mark is removed before an enemy attacks the stack (counterattacks do not get the prepared effect)
function L.ensureTracker(server, battle, unit)
	local has = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return b:getStacking() == "h7StatusTick" end)
	if has:size() > 0 then return end
	server:addBattleBonus(battle, {
		type = "COMBAT_EVENT_TRIGGER", subtype = "h7StatusTick", val = 0, hidden = true,
		duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h7StatusTick"
	})
end

function L.refundCast(server, battle, caster)
	server:addUnitBonus(battle, caster, {
		type       = "CASTS",
		val        = 1,
		valueType  = ENUM.BonusValueType.additiveValue,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = caster:getCreature():getJsonKey(),
		hidden     = true
	}, true)
end

--- "nTurns" / {"untilAfterAttackSequence", "nTurns"} / number -> engine duration
function L.duration(d)
	if d == nil then return ENUM.BonusDuration.oneBattle end
	if type(d) == "number" then return d end
	if type(d) == "string" then return ENUM.BonusDuration[d] or ENUM.BonusDuration.oneBattle end
	local sum = 0
	for _, k in ipairs(d) do sum = sum + (ENUM.BonusDuration[k] or 0) end
	return sum
end

function L.addBonus(server, battle, unit, desc)
	local d = {}
	for k, v in pairs(desc) do d[k] = v end
	d.duration = L.duration(desc.duration)
	if type(d.valueType) == "string" then d.valueType = ENUM.BonusValueType[d.valueType] end
	d.valueType = d.valueType or ENUM.BonusValueType.additiveValue
	d.sourceType = d.sourceType or ENUM.BonusSource.other
	d.sourceID = d.sourceID or unit:getCreature():getJsonKey()
	if d.val == nil then d.val = 0 end
	if d.hidden == nil then d.hidden = true end
	server:addUnitBonus(battle, unit, d, true)
end

local function accessible(battle, unit, h)
	if h == nil or not h:isValid() or not h:isAvailable() then return false end
	local ok, res = pcall(function() return battle:isAccessibleForUnit(unit, h) end)
	return ok and res
end
L.accessible = accessible

function L.freeHexNextTo(battle, unit, target, from)
	local around = target:getSurroundingHexes()
	local best, bestD = nil, 1000
	for i = 1, around:size() do
		local h = around:at(i)
		if accessible(battle, unit, h) then
			local d = from and L.hexDistance(h, from) or 0
			if d < bestD then best, bestD = h, d end
		end
	end
	return best
end

function L.nearestFree(battle, unit, hex)
	if accessible(battle, unit, hex) then return hex end
	local best, bestD = nil, 1000
	for _, h in pairs(L.hexTable(battle)) do
		if accessible(battle, unit, h) then
			local d = L.hexDistance(h, hex)
			if d < bestD then best, bestD = h, d end
		end
	end
	return best
end

function L.reviveHeal(unit, amount)
	local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if ok and ring then
		if not unit:isAlive() then return 0, ENUM.HealLevel.heal end
		return math.min(amount, unit:getMaxHealth() - unit:getFirstHPleft()), ENUM.HealLevel.heal
	end
	return amount, ENUM.HealLevel.resurrect
end

--- Stack size x random damage (above 10 creatures sampled as 10 and scaled up) x attack/defense modifier (+5% per point of higher attack, at most +300%; -2.5% per point of higher defense, at most -70%) x pct%
--- H7 audit A3: reductions on the target that engine attack damage also applies (armorer / magicShield / petrification of damageCalculator, multiplied together):
--- armor-type all-damage reduction (non-spell sources: Raise Shields, Rune of Balance, Shadow Cloak etc.), shield / air shield depending on range, all-damage reduction from spells such as Petrify.
--- Ranged attacks on targets inside a Mist Veil (H7_FOGSHROUD_H7C) are 0 (as damage/h7FogShroudPatch). Returns a multiplier from 0 to 1.
local function reductionFactor(target, ranged)
	local ok, r = pcall(function()
		if ranged and target:hasBonuses({ type = "H7_FOGSHROUD_H7C" }) then return 0 end
		local armor = target:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
			return b:getSource() ~= ENUM.BonusSource.spellEffect
		end):totalValue()
		local shield = target:getBonusesValue({ type = "GENERAL_DAMAGE_REDUCTION", subtype = ranged and "damageTypeRanged" or "damageTypeMelee" }) or 0
		local petrify = target:getBonusesValue({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", sourceType = ENUM.BonusSource.spellEffect }) or 0
		local f = 1
		for _, v in ipairs({ armor, shield, petrify }) do f = f * (100 - math.max(0, math.min(100, v))) / 100 end
		return f
	end)
	if ok and type(r) == "number" then return r end
	return 1
end
--- H7 audit A3: the result is also multiplied by the target's reduction (armor-type, shield / air shield, Petrify; 0 for ranged on a Mist Veil)
function L.rollDamage(server, attacker, target, attackBonus, pct, ranged)
	local red = reductionFactor(target, ranged or false)
	if red <= 0 then return 0 end
	local count = attacker:getCount()
	local minD = attacker:getMinDamage(ranged or false)
	local maxD = math.max(minD, attacker:getMaxDamage(ranged or false))
	local base = 0
	if count <= 10 then
		for _ = 1, count do base = base + server:rngInt(minD, maxD) end
	else
		for _ = 1, 10 do base = base + server:rngInt(minD, maxD) end
		base = base * count / 10
	end
	local diff = attacker:getAttack(ranged or false) + (attackBonus or 0) - target:getDefense(ranged or false)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * (pct or 100) / 100 * red))
end

return L
