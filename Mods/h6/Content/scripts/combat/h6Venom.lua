local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Venomous Touch (H6 Fate Spinner, Fate Weaver)
---
--- Stacks that attack it in melee or are attacked by it in melee (counterattacks included) are poisoned: at the start of each of the next turns rounds they take per x number of Spinners Earth damage
--- (settled by the battle-wide h6Dot). Being poisoned again replaces the old share; it does not stack.
--- Parameters: per, turns

local function poison(self, server, battle, unit, target)
	if target == nil or not L.real(target) or not battle:isHostile(unit, target) then return end
	L.addDot(server, battle, target, "venom" .. tostring(unit:getSide()), (self.per or 10) * unit:getCount(), self.turns or 3)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or not unit:isAlive() then return end
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and t.unit:isAlive() then poison(self, server, battle, unit, t.unit) end
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or not unit:isAlive() then return end
	if other and other:isAlive() then poison(self, server, battle, unit, other) end
end

return Script
