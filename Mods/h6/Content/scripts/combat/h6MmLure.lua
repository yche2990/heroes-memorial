--- Lure of Displacement (H6 Memorial Sanctum, Dungeon): disappears at the start of the next round.
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other, payload)
	if unit:isAlive() then server:removeUnit(battle, unit); server:refreshBattleUnits(battle) end
end

return Script
