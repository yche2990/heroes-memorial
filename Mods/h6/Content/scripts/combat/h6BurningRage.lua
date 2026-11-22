local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Burning Rage (H6 Wrathful Cyclops): after a shot hits, the target takes pct% of this damage at the start of each of the next turns rounds
--- as damage over time (settled by the battle-wide h6Dot). Parameters: pct, turns

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or not unit:isAlive() then return end
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and t.unit:isAlive() and battle:isHostile(unit, t.unit) and (t.damage or 0) > 0 then
			L.addDot(server, battle, t.unit, "burn" .. tostring(unit:getSide()), math.max(1, math.floor(t.damage * (self.pct or 20) / 100)), self.turns or 2)
		end
	end
end

return Script
