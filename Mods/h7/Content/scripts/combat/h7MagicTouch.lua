local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Magic Touch (Djinn Vizier)
---
--- After its attack (counterattacks included) hits an enemy, it gets a random negative spell (original spells, Expert effects, see h7StatusLib.DEBUFFS),
--- and the one this table added before is removed. Spells it is immune to are never drawn.

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil then return end
	local entry = self:ownEntry(other, payload)
	if entry == nil or (entry.damage or 0) <= 0 or not other:isAlive() then return end
	L.randomDebuff(server, battle, unit, other)
end

return Script
