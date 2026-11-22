local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Shield of Chaos (Efreet)
---
--- Each time an enemy attacks the Efreet in melee (counterattacks on the Efreet included), the attacker gets a random negative spell
--- (original spells, Expert effects, see h7StatusLib.DEBUFFS), and the one this table added before is removed. Not triggered if the Efreet is already dead.

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or other == nil or not unit:isAlive() or not other:isAlive() then return end
	if other:unitID() == unit:unitID() then return end
	L.randomDebuff(server, battle, unit, other)
end

return Script
