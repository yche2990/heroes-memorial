local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Battle Frenzy (Battle Griffin)
--- Each retaliation deals val% of the previous one (150 = 1.5 times): the n-th retaliation (counting from 0) deals damage x (val/100)^n, cumulative for the whole battle.
--- How: before the retaliation strike a melee damage bonus is attached by the number of retaliations so far, +1 after the retaliation. Parameter: val

local STACK = "h5BattleFrenzy"

function Script:onBeforeAttack(server, battle, unit, other, payload)
	H5.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
	if not payload.isCounter then return end
	local n = H5.markValue(unit, STACK) or 0
	if n <= 0 then return end
	local mult = ((self.val or 150) / 100) ^ n
	local pct = math.floor((mult - 1) * 100 + 0.5)
	if pct <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = STACK, hidden = true
	}, false)
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	H5.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
	if not payload.isCounter then return end
	local n = (H5.markValue(unit, STACK) or 0) + 1
	H5.setMark(server, battle, unit, STACK, n, nil)
end

return Script
