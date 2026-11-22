--- Annulment (H6): no beneficial spells while it lasts; a beneficial spell received is dispelled.
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() or payload.spell == nil or not payload.spell:isPositive() then return end
	S.removeSpell(server, battle, unit, payload.spell:getJsonKey())
end

return Script
