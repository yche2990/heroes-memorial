--- H6 memorial Gating charge (given to the hero's stacks by the Tears of Ashan Gating skill; only H6 Inferno creatures count). Original: +50 when a friendly stack lands a lucky or unlucky strike.
--- The engine does not tell scripts whether a hit was lucky, so instead every attack (counterattacks included) is scaled by Luck: +10, plus +10 per point of Luck or bad luck (at most 3 points).
local Base = require("combat/combatScript")
local R = require("lib/h6RcLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not server:describeChanges() or not R.has(unit, "H6_GATING_H6C") then return end   -- Only attacks of H6 Inferno creatures count
	local luck = 0
	pcall(function() luck = unit:getLuck() end)
	R.addGauge(server, battle, unit:getSide(), "gate", 10 + 10 * math.min(3, math.abs(luck or 0)))
end

return Script
