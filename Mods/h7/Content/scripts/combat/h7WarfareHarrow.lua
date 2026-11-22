local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Terrifying Visions (Shadow Lurker, see combat/h7WarfareHarrowShot): on the enemy hit; it takes val Dark damage at the start of each round, with the remaining rounds in a mark.

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local v = W.effectVal(unit, "h7WarfareHarrow")
	if v == nil then return end
	local dealt = W.schoolHit(server, battle, unit, v, "dark", "h7/fx/h7wfHarrowTick")
	if dealt > 0 then W.log(server, battle, 3, { W.name(unit) }, { dealt }) end
	if unit:isAlive() then W.tickLeft(server, battle, unit, "h7WarfareHarrow") end
end

return Script
