local Base = require("combat/combatScript")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Imp (Mana Steal) / Devil Spawn (Mana Destruction)
---
--- Original: at battle start the enemy hero loses perGrowth x count / weekly growth mana (original ManaStealPerWeekPopulation = 4,
--- about 0.25 per creature), and what is stolen goes to the own hero.
--- Lua cannot change hero mana, so as an approximation: at battle start it gets an engine MANA_DRAIN lasting only round 1 (value by the formula above),
--- which the engine takes from the enemy hero when this stack's turn comes in round 1 (nothing if there is no hero, or the stack dies before its round 1 turn).
--- The share given to the own hero by the stealing kind comes from the creature's own COMBAT_MANA_BONUS (passed to the hero, scaled by count), present from battle start,
--- not limited by the enemy hero's remaining mana.
---
--- Parameters: mode (destroy / steal), perGrowth

function Script:onBattleStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isClone() or L.isSummoned(unit) then return end
	local growth = L.value(unit, { type = "H5_GROWTH_H5C" })
	if growth <= 0 then growth = math.max(1, unit:getCreature():getGrowth()) end
	local amount = math.floor((self.perGrowth or 4) * unit:getCount() / growth + 0.5)
	if amount <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type = "MANA_DRAIN", val = amount,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.creatureAbility, sourceID = unit:getCreature():getJsonKey(),
		stacking = "h5ManaBurn", hidden = true
	}, false)
end

return Script
