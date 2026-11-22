--- Burning Heart (H6): Morale cannot be lowered by magic while it lasts; a morale-lowering spell received is dispelled.
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	S.dispelBySign(server, battle, unit, "MORALE", -1, nil)
end

return Script
