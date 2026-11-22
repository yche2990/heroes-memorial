local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Take Roots (Ancient Treant)
--- When it waits or defends, Defense +val%, and unlimited retaliation until the end of its next action.
--- Removed at the end of its next action (acting again in the same round after waiting also counts). Parameter: val (Defense bonus percent)

local STACK = "h5TakeRoots"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
	H5.removeByStacking(server, battle, unit, "UNLIMITED_RETALIATIONS", STACK)
	H5.removeByStacking(server, battle, unit, "H5_ROOTS_SHOW_H5C", STACK)
	H5.clearMark(server, battle, unit, STACK)
end

function Script:root(server, battle, unit)
	if not unit:isAlive() then return end
	clear(server, battle, unit)
	local src = unit:getCreature():getJsonKey()
	local function add(d)
		d.duration = ENUM.BonusDuration.nTurns; d.turns = 2
		d.sourceType = ENUM.BonusSource.other; d.sourceID = src; d.stacking = STACK
		server:addUnitBonus(battle, unit, d, false)
	end
	add({ type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = self.val or 50, valueType = ENUM.BonusValueType.percentToBase, hidden = true })
	add({ type = "UNLIMITED_RETALIATIONS", val = 0, hidden = true })
	add({ type = "H5_ROOTS_SHOW_H5C", val = self.val or 50 })
	-- Mark value 1 = just rooted (not removed at the end of this action), 2 = removed at the end of the next action
	H5.setMark(server, battle, unit, STACK, 1, 2)
	server:refreshBattleUnits(battle)
end

function Script:onWait(server, battle, unit, other, payload) self:root(server, battle, unit) end
function Script:onDefend(server, battle, unit, other, payload) self:root(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local m = H5.markValue(unit, STACK)
	if m == nil then return end
	if m == 1 then
		H5.setMark(server, battle, unit, STACK, 2, 2)
	else
		clear(server, battle, unit)
	end
end

return Script
