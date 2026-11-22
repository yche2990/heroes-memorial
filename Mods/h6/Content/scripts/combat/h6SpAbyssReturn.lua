--- Abyssal Gate (H6): a stack that returned to the Abyss comes back at the start of the next round: this spell's effect is removed and reinforcements of the same kind are summoned in the nearest free hex (summoned, gone after battle).
--- Parameters: spell, hp (total health of the reinforcements)
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	S.removeSpell(server, battle, unit, self.spell)
	local creature = unit:getCreature()
	local count = math.max(1, math.floor((self.hp or 0) / math.max(1, unit:getMaxHealth())))
	local hex = battle:getAvailableHex(creature, unit:getSide(), unit:getPosition())
	if hex ~= nil and hex:isValid() then
		server:addUnit(battle, { count = count, type = creature, side = unit:getSide(), position = hex, summoned = true })
	end
	server:refreshBattleUnits(battle)
end

return Script
