local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Taste of Pain (H6 Tormentor, Lacerator)
---
--- Each attack made or received (counterattacks included) adds 1 layer, up to max layers; the next attack deals +layers x pct% damage and uses up all layers
--- (and gains 1 layer again when it hits). Layers show on H6_TASTE_H6C (value = current damage bonus). Parameters: pct, max

local TAG = "h6Taste"

local function stacks(unit, pct)
	local v = 0
	local list = unit:getBonuses({ type = "H6_TASTE_H6C" })
	for i = 1, list:size() do v = math.max(v, list:getBonus(i):getVal()) end
	return math.floor(v / pct)
end

local function set(server, battle, unit, n, pct)
	L.removeByStacking(server, battle, unit, "H6_TASTE_H6C", TAG)
	if n > 0 then L.addBonus(server, battle, unit, { type = "H6_TASTE_H6C", val = n * pct, stacking = TAG }, false) end
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	local pct = self.pct or 15
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	local n = stacks(unit, pct)
	if n > 0 and unit:isAlive() then
		L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = n * pct, hidden = true,
			duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = TAG }, false)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	local pct = self.pct or 15
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	if unit:isAlive() then set(server, battle, unit, 1, pct) end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local pct = self.pct or 15
	set(server, battle, unit, math.min(self.max or 4, stacks(unit, pct) + 1), pct)
end

return Script
