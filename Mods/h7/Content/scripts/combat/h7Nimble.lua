local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Nimble (Mole Scout)
--- Defense +val when attacked or counterattacked by a large (two-hex) enemy (original +10, scaled to +13 by level 1 Attack/Defense), melee and ranged.
--- "Cannot be flanked by large creatures" is the hidden mark H7_NO_FLANK_H7C (value 2) on the creature, read by flanking scripts.

local TMP = "h7NimbleTmp"

local function clear(server, battle, unit)
	A.removeByStacking(server, battle, unit, "PRIMARY_SKILL", TMP)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	clear(server, battle, unit)
	if other == nil or not unit:isAlive() then return end
	if not battle:isHostile(other, unit) then return end
	if not other:getCreature():isDoubleWide() then return end
	server:addUnitBonus(battle, unit, {
		type = "PRIMARY_SKILL", subtype = "primarySkill.defence", val = self.val or 13,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(),
		stacking = TMP, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	clear(server, battle, unit)
end

return Script
