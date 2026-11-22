local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Agility (Wind Dancer)
--- After each move, Defense +val per hex moved, until the end of its next action. Parameter: val (Defense bonus per hex)

local STACK = "h5Agility"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
	H5.removeByStacking(server, battle, unit, "H5_AGILITY_SHOW_H5C", STACK)
	H5.clearMark(server, battle, unit, STACK)
end

function Script:onBeforeMove(server, battle, unit, other, payload)
	H5.recordMoveStart(server, battle, unit)
end

function Script:onAfterMove(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	H5.recordMoveEnd(server, battle, unit)
	local cells = H5.movedCells(unit)
	if cells <= 0 then return end
	clear(server, battle, unit)
	local v = (self.val or 2) * cells
	local src = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = v,
		duration = ENUM.BonusDuration.nTurns, turns = 2, sourceType = ENUM.BonusSource.other, sourceID = src,
		stacking = STACK, hidden = true
	}, false)
	server:addUnitBonus(battle, unit, {
		type = "H5_AGILITY_SHOW_H5C", val = v,
		duration = ENUM.BonusDuration.nTurns, turns = 2, sourceType = ENUM.BonusSource.other, sourceID = src,
		stacking = STACK
	}, false)
	H5.setMark(server, battle, unit, STACK, 1, 2)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	H5.clearMove(server, battle, unit)
	local m = H5.markValue(unit, STACK)
	if m == nil then return end
	if m == 1 then
		H5.setMark(server, battle, unit, STACK, 2, 2)
	else
		clear(server, battle, unit)
	end
end

return Script
