--- H6 memorial hero spells, batch 3: zones settle once at the start of each round (spells/h6SpZone adds one entry to the battlefield per cast).
--- Handled by the living stack with the lowest id; does nothing once all of the zone's obstacles are gone. Parameters: see zoneTick in lib/h6SpLib
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other, payload)
	local first = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() end)) do
		if first == nil or u:unitID() < first then first = u:unitID() end
	end
	if first ~= unit:unitID() then return end
	S.zoneTick(server, battle, self)
end

return Script
