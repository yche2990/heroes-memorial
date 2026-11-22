--- H6 memorial racial abilities (round 418, Yu's decision: done as in H6, attached to the Tears of Ashan Gating and Blood Rage skills): shared helpers.
--- Not registered as a script; loaded with require("lib/h6RcLib").
---   Charge bars: one per side (one each for Gating gate and Blood Rage rage), full at 400. The value is stored on every stack of that side with this charge enabled
---           (hidden mark + visible charge display), and reading takes the side's maximum, so stacks summoned later can read it too.
---   M.enabled(u, kind)        whether the stack's side has it enabled (H6_RC_GATE_ON_H6C / H6_RC_RAGE_ON_H6C from the skill)
---   M.gauge(battle, side, kind), M.setGauge(server, battle, side, kind, v), M.addGauge(...)
---   M.setRage(server, battle, u, level, turns), M.rageLevel(u)   effects of H6 Blood Rage I-IV on a stack
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local M = {}
M.MAX = 400
M.KIND = {
	gate = { on = "H6_RC_GATE_ON_H6C", show = "H6_RC_GATE_GAUGE_H6C", key = "h6RcGateGauge" },
	rage = { on = "H6_RC_RAGE_ON_H6C", show = "H6_RC_RAGE_GAUGE_H6C", key = "h6RcRageGauge" },
}

local function has(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r == true
end
M.has = has

function M.enabled(u, kind) return u ~= nil and has(u, M.KIND[kind].on) end

local function sideUnits(battle, side, kind)
	return battle:getUnitsIf(function(u) return u:getSide() == side and u:isAlive() and M.enabled(u, kind) end)
end

function M.sideEnabled(battle, side, kind) return #sideUnits(battle, side, kind) > 0 end

function M.gauge(battle, side, kind)
	local best = 0
	for _, u in ipairs(sideUnits(battle, side, kind)) do
		local v = L.markValue(u, M.KIND[kind].key) or 0
		if v > best then best = v end
	end
	return best
end

function M.setGauge(server, battle, side, kind, v)
	local k = M.KIND[kind]
	v = math.max(0, math.min(M.MAX, math.floor(v)))
	for _, u in ipairs(sideUnits(battle, side, kind)) do
		if (L.markValue(u, k.key) or -1) ~= v then
			L.setMark(server, battle, u, k.key, v)
			local list = u:getBonuses({ type = k.show }):filter(function(b) return b:getStacking() == k.key end)
			if list:size() > 0 then Proxy.removeExact(server, battle, u, list) end
			server:addUnitBonus(battle, u, { type = k.show, val = v, duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other,
				sourceID = u:getCreature():getJsonKey(), stacking = k.key }, true)
		end
	end
end

function M.addGauge(server, battle, side, kind, d)
	if d == 0 or not M.sideEnabled(battle, side, kind) then return end
	M.setGauge(server, battle, side, kind, M.gauge(battle, side, kind) + d)
end

-- ---- H6 Blood Rage I-IV (original: Initiative +5/+5/+5/+10 -> Speed +1/+1/+1/+2; physical attack +10/+15 -> Attack +2/+3 (divided by 4.3);
--      III and IV one extra counterattack; IV briefly stuns on attack, the target cannot counterattack)
M.RAGE = {
	{ speed = 1 },
	{ speed = 1, attack = 2 },
	{ speed = 1, attack = 2, retal = 1 },
	{ speed = 2, attack = 3, retal = 1, block = true },
}
local RK = "h6RcRage"

--- Highest Blood Rage level this side can reach (Tears of Ashan Blood Rage skill: Basic II, Advanced III, Expert IV, stored in the value of H6_RC_RAGE_ON_H6C)
function M.rageMax(battle, side)
	local best = 0
	for _, u in ipairs(sideUnits(battle, side, "rage")) do
		local list = u:getBonuses({ type = M.KIND.rage.on })
		for i = 1, list:size() do
			local v = list:getBonus(i):getVal()
			if v > best then best = v end
		end
	end
	return math.min(4, best)
end

function M.isRager(u) return u ~= nil and u:isAlive() and not u:isGhost() and has(u, "H6_BLOODRAGE_H6C") end

function M.rageLevel(u)
	local list = u:getBonuses({ type = "H6_RAGE_LV_H6C" }):filter(function(b) return b:getStacking() == RK end)
	if list:size() == 0 then return 0, 0 end
	local b = list:getBonus(1)
	return b:getVal(), b:getTurnsRemain()
end

function M.clearRage(server, battle, u)
	for _, t in ipairs({ "STACKS_SPEED", "PRIMARY_SKILL", "ADDITIONAL_RETALIATION", "BLOCKS_RETALIATION", "H6_RAGE_LV_H6C" }) do
		L.removeByStacking(server, battle, u, t, RK)
	end
end

function M.setRage(server, battle, u, level, turns)
	M.clearRage(server, battle, u)
	level = math.max(0, math.min(4, level))
	if level == 0 then return end
	local e = M.RAGE[level]
	local src = u:getCreature():getJsonKey()
	local function add(d)
		d.duration = ENUM.BonusDuration.nTurns; d.turns = turns; d.sourceType = ENUM.BonusSource.other; d.sourceID = src; d.stacking = RK
		if d.hidden == nil then d.hidden = true end
		server:addUnitBonus(battle, u, d, true)
	end
	add({ type = "STACKS_SPEED", val = e.speed })
	if e.attack then add({ type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = e.attack }) end
	if e.retal then add({ type = "ADDITIONAL_RETALIATION", val = e.retal }) end
	if e.block then add({ type = "BLOCKS_RETALIATION", val = 0 }) end
	add({ type = "H6_RAGE_LV_H6C", val = level, hidden = false })
end

-- ---- H6 Gating ----------------------------------------------------------------------------
--- Summon: place count summons of the same kind as tpl on hex (nearest free hex if it does not fit), record the source and attach the link back to the Abyss (unsummonFx, unsummonSound are the effect and sound when returning)
function M.summon(server, battle, tpl, count, hex, fx, sound, unsummonFx, unsummonSound)
	local cr = tpl:getCreature()
	local side = tpl:getSide()
	local ok, acc = pcall(function() return battle:isAccessibleForNewUnit(hex, cr, side) end)
	if not (ok and acc) then hex = battle:getAvailableHex(cr, side, hex) end
	if hex == nil or not hex:isValid() then return nil end
	local s = server:addUnit(battle, { count = count, type = cr, side = side, position = hex, summoned = true })
	if s == nil then s = battle:getUnitByPos(hex, true) end
	if s == nil then return nil end
	L.setMark(server, battle, s, "h6RcGated", tpl:unitID() + 1)
	server:addUnitBonus(battle, s, { type = "H6_RC_GATED_H6C", val = 1, duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other,
		sourceID = cr:getJsonKey(), stacking = "h6RcGated", icon = "h6/abilities/rc_GatingI" }, true)
	server:addUnitBonus(battle, tpl, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6RcGatedLink", val = s:unitID(), hidden = true,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = cr:getJsonKey(),
		stacking = "h6RcGatedLink" .. tostring(s:unitID()), addInfo = { fx = unsummonFx, sound = unsummonSound } }, true)
	if fx and server:describeChanges() then server:showBattleAnimation(battle, { { unit = s } }, fx, sound or "", 1.0, true) end
	return s
end


return M
