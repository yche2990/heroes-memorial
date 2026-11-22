local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Hunger (H6 Forest Wolf, Dire Wolf): Speed +speed in the first round. Parameter: speed

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() then return end
	server:addUnitBonus(battle, unit, { type = "STACKS_SPEED", val = self.speed or 2, duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.creatureAbility, sourceID = unit:getCreature():getJsonKey(), stacking = "h6Hunger" }, true)
end

return Script
