--- Petrify (H6, on own troops): a petrified friendly stack can act; acting ends the petrification. Parameter: spell (full spell name)
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	S.removeSpell(server, battle, unit, self.spell)
end

return Script
