local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Prepared Position (Mountain Guard)
--- Defense +val while it stays where it was placed in the tactics phase; lost for good once it leaves (not regained by returning).
--- The position is recorded at battle start (after tactics) and checked at the end of every move and the start of every round. Parameter: val

local STACK = "h5PreparedPosition"

local function drop(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PRIMARY_SKILL", STACK)
	H5.removeByStacking(server, battle, unit, "H5_PREPARED_SHOW_H5C", STACK)
end

function Script:onBattleStart(server, battle, unit, other)
	if not unit:isAlive() then return end
	drop(server, battle, unit)
	local src = unit:getCreature():getJsonKey()
	local v = self.val or 5
	server:addUnitBonus(battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = v,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src,
		stacking = STACK, hidden = true
	}, false)
	server:addUnitBonus(battle, unit, {
		type = "H5_PREPARED_SHOW_H5C", val = v,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src,
		stacking = STACK
	}, false)
	H5.setMark(server, battle, unit, STACK, H5.hexIndex(unit:getPosition()), nil)
end

function Script:check(server, battle, unit)
	local home = H5.markValue(unit, STACK)
	if home == nil or home < 0 then return end
	if H5.hexIndex(unit:getPosition()) ~= home then
		drop(server, battle, unit)
		H5.setMark(server, battle, unit, STACK, -1, nil)
	end
end

function Script:onAfterMove(server, battle, unit, other, payload) self:check(server, battle, unit) end
function Script:onRoundStart(server, battle, unit, other) self:check(server, battle, unit) end
function Script:onActionFinished(server, battle, unit, other, payload) self:check(server, battle, unit) end

return Script
