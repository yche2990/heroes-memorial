local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Regeneration (Deep Hydra, Wyvern, Venomous Wyvern)
--- Restores min-max health (random) at the start of each round, healing only the top creature, no resurrection.
--- All stacks are at full health in round 1, so only onRoundStart is hooked. Parameters: min, max

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local missing = unit:getMaxHealth() - unit:getFirstHPleft()
	if missing <= 0 then return end
	local lo, hi = self.min or 30, self.max or 50
	if hi < lo then hi = lo end
	local amount = math.min(missing, server:rngInt(lo, hi))
	server:showBattleAnimation(battle, { { unit = unit } }, "h5/fx/Spells_Heal", "", 0.8, true)
	server:healUnit(battle, unit, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.7", { H5.name(unit) }, { amount })
end

return Script
