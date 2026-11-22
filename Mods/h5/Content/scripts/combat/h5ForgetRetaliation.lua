local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Confusion, retaliation part: X% of the stack forget to retaliate, retaliation damage -X% (X = its own H5_FORGET_H5C value).
--- The ranged part is handled by the spell's own ranged damage reduction. The damage formula cannot tell whether it is a retaliation, so the Confusion spell
--- attaches this script to the target with attachCombatScript (same duration as the spell); a melee damage reduction is attached before the retaliation strike and removed after.

local STACK = "h5ForgetRetaliation"

local function clear(server, battle, unit)
	H5.removeByStacking(server, battle, unit, "PERCENTAGE_DAMAGE_BOOST", STACK)
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if not payload.isCounter then return end
	local x = math.min(100, unit:getBonusesValue({ type = "H5_FORGET_H5C" }))
	if x <= 0 then return end
	for _, sub in ipairs({ "damageTypeMelee", "damageTypeRanged" }) do
		server:addUnitBonus(battle, unit, {
			type = "PERCENTAGE_DAMAGE_BOOST", subtype = sub, val = -x,
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
