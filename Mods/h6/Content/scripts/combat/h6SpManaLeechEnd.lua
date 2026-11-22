--- Mana Leech (H6) cleanup: the engine drains mana when the stack carrying MANA_DRAIN starts acting; once it finishes acting, this spell's bonus is removed so mana is drained only once.
--- With minTurns = 1 (handed to the stack that was acting when the spell was cast) it is removed only after an action from the next round on (remaining rounds <= 1). Parameters: spell, minTurns
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local list = unit:getBonuses({ type = "MANA_DRAIN" }):filter(function(b) return b:getSourceID() == self.spell end)
	if list:size() == 0 then return end
	if list:getBonus(1):getTurnsRemain() > (self.minTurns or 2) then return end
	S.removeSpell(server, battle, unit, self.spell)
end

return Script
