local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Fast Attack (Earth Daughter): when attacking a slowed target (speed reduced by any spell, e.g. Mass Slow), the target cannot retaliate.
--- How: if the target is slowed before the strike, it gets "no retaliation", removed at the end of this action.

local STACK = "h5FastAttack"

local function slowed(t)
	return t:getBonusesValue({ type = "STACKS_SPEED", sourceType = ENUM.BonusSource.spellEffect }) < 0
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload.isCounter then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	if not slowed(entry.unit) then return end
	if unit:hasBonuses({ type = "BLOCKS_RETALIATION" }) then return end
	server:addUnitBonus(battle, unit, {
		type = "BLOCKS_RETALIATION", val = 0,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = STACK, hidden = true
	}, false)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	H5.removeByStacking(server, battle, unit, "BLOCKS_RETALIATION", STACK)
end

return Script
