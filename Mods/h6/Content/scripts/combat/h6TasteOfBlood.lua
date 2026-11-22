local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Taste of Blood (H6 Brute, Crusher)
---
--- Damage +pct% each time it is attacked (counterattacks included), up to max layers, until the battle ends. The original is "minimum damage +1",
--- converted to a percentage for this damage scale. Parameters: pct, max

local TAG = "h6Blood"

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local pct, max = self.pct or 10, self.max or 4
	local cur = 0
	local list = unit:getBonuses({ type = "H6_BLOOD_H6C" })
	for i = 1, list:size() do cur = math.max(cur, list:getBonus(i):getVal()) end
	local n = math.min(max, math.floor(cur / pct) + 1)
	if n * pct == cur then return end
	L.removeByStacking(server, battle, unit, "H6_BLOOD_H6C", TAG)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", TAG)
	L.addBonus(server, battle, unit, { type = "H6_BLOOD_H6C", val = n * pct, stacking = TAG }, false)
	L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = n * pct, hidden = true, stacking = TAG }, false)
end

return Script
