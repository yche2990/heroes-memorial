local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Fierce Retaliation (Bloodthirsty): retaliation deals val% of normal damage (200 = double). Parameter: val

local STACK = "h5FierceRetaliation"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if not payload.isCounter then return end
	local pct = (self.val or 200) - 100
	if pct <= 0 then return end
	for _, sub in ipairs({ "damageTypeMelee", "damageTypeRanged" }) do
		server:addUnitBonus(battle, unit, {
			type = "PERCENTAGE_DAMAGE_BOOST", subtype = sub, val = pct,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
			stacking = STACK, hidden = true
		}, true)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
end

return Script
