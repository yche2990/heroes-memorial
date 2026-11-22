--- Shared functions of the H7 memorial Blood Rage (Stronghold racial skill, Yu's decision 2026-11-01).
--- The Blood Rage value is shared by a side: every H7 Stronghold creature on that side (with H7_BLOODRAGE_H7C) carries the same two whole-battle bonuses:
---   PRIMARY_SKILL attack +R (hidden, stacking h7BloodRage) and H7_RAGE_SHOW_H7C val R (shows "Blood Rage Attack +R", stacking h7BloodRageShow).
--- Reading the value reads H7_RAGE_SHOW_H7C on any Stronghold creature of the side; changing it changes all Stronghold creatures of the side together.
--- Hero level: Stronghold creatures carry the hidden H7_RAGE_LV_H7C (propagator HERO + TIMES_HERO_LEVEL), so the value the stack reads is the hero level; 0 without a hero.

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}
M.RAGED = "H7_BLOODRAGE_H7C"
M.LV = "H7_RAGE_LV_H7C"
M.SHOW = "H7_RAGE_SHOW_H7C"
local ATK_KEY, SHOW_KEY = "h7BloodRage", "h7BloodRageShow"

local function bystack(unit, typeName, key)
	return unit:getBonuses({ type = typeName }):filter(function(b) return b:getStacking() == key end)
end

function M.isRager(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and u:hasBonuses({ type = M.RAGED })
end

--- Hero level (0 without a hero)
function M.heroLevel(u)
	local list = u:getBonuses({ type = M.LV })
	local best = 0
	for i = 1, list:size() do
		local v = list:getBonus(i):getVal()
		if v > best then best = v end
	end
	return best
end

function M.hasHero(u)
	return u:hasBonuses({ type = "PRIMARY_SKILL", sourceType = ENUM.BonusSource.heroBaseSkill })
end

--- Blood Rage at battle start: 6, +3 at hero level 10, +3 at level 20; 0 without a hero (Yu's decision; the Stronghold guards of the Memorial Sanctum get 6 from h7SanctumTwin.lua instead)
M.SANCTUM_START = 6
function M.startValue(u)
	if not M.hasHero(u) then return 0 end
	local lv = M.heroLevel(u)
	local r = 6
	if lv >= 10 then r = r + 3 end
	if lv >= 20 then r = r + 3 end
	return r
end

function M.get(u)
	local list = bystack(u, M.SHOW, SHOW_KEY)
	if list:size() == 0 then return 0 end
	return list:getBonus(1):getVal()
end

function M.setOne(server, battle, u, r)
	local a = bystack(u, "PRIMARY_SKILL", ATK_KEY)
	if a:size() > 0 then Proxy.removeExact(server, battle, u, a) end
	local s = bystack(u, M.SHOW, SHOW_KEY)
	if s:size() > 0 then Proxy.removeExact(server, battle, u, s) end
	if r <= 0 then return end
	local src = u:getCreature():getJsonKey()
	server:addUnitBonus(battle, u, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = r, hidden = true, stacking = ATK_KEY,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src
	}, true)
	server:addUnitBonus(battle, u, {
		type = M.SHOW, val = r, stacking = SHOW_KEY,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src
	}, true)
end

function M.sideRagers(battle, side)
	return battle:getUnitsIf(function(u) return u:getSide() == side and M.isRager(u) end)
end

--- Set the side's Blood Rage to r (all Stronghold creatures together, at least 0)
function M.setSide(server, battle, side, r)
	if r < 0 then r = 0 end
	for _, u in ipairs(M.sideRagers(battle, side)) do M.setOne(server, battle, u, r) end
end

--- The side's current Blood Rage (the largest among its Stronghold creatures; 0 if none)
function M.sideValue(battle, side)
	local best = 0
	for _, u in ipairs(M.sideRagers(battle, side)) do
		local v = M.get(u)
		if v > best then best = v end
	end
	return best
end

return M
