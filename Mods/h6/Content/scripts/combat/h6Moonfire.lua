local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Moonfire Aura (H6 Phoenix): after the Phoenix attacks an enemy (each enemy hit by the blow, breath splash included) or is attacked by one (melee or ranged),
--- that enemy also takes per x number of Phoenixes Prime damage (no school, scaled only by all-spell reduction). Parameters: per, animation, sound
--- Review B10 (2026-11-08): changed to match the description "enemies that attack it or are attacked by it": it used to burn only the first target and only melee attackers; now every target hit burns,
--- and shooters burn too. An enemy counterattacking the Phoenix is no longer burned separately (it is the target just hit and already burned); the Phoenix's second strike does not burn again.

local function burn(self, server, battle, unit, enemy)
	if not L.real(enemy) or not battle:isHostile(unit, enemy) then return end
	local a = math.floor((self.per or 10) * unit:getCount() * (100 - L.schoolReduction(enemy, nil)) / 100)
	if a > 0 then L.hit(server, battle, enemy, a, self.animation, self.sound) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or (payload.attackIndex or 0) > 0 then return end
	local seen = {}
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and not seen[t.unit:unitID()] then
			seen[t.unit:unitID()] = true
			burn(self, server, battle, unit, t.unit)
		end
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil or payload.isCounter then return end
	burn(self, server, battle, unit, other)
end

return Script
