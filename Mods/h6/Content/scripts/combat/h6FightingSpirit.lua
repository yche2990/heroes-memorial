local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Fighting Spirit (H6 Minotaur Guard): Morale +1 after each of its own attacks (counterattacks excluded), up to +max, until the battle ends, cannot be dispelled.
--- Parameters: max (default 3), animation, sound

local KEY = "h6FightingSpirit"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or (payload.attackIndex or 0) > 0 or not unit:isAlive() then return end
	local cur = L.markValue(unit, KEY) or 0
	if cur >= (self.max or 3) then return end
	cur = cur + 1
	L.setMark(server, battle, unit, KEY, cur)
	L.removeByStacking(server, battle, unit, "MORALE", KEY)
	server:addUnitBonus(battle, unit, {
		type = "MORALE", val = cur, duration = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.creatureAbility, sourceID = unit:getCreature():getJsonKey(), stacking = KEY
	}, true)
	L.show(server, battle, { unit }, self.animation, self.sound)
end

return Script
