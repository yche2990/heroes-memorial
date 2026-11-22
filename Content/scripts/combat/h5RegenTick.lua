local Base = require("combat/combatScript")
local H5R = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Regeneration (put on by the spell h5Regeneration): restores val health at the start of each round, can resurrect fallen creatures of this stack (until the end of this battle).

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local amount = self.val or 0
	if amount <= 0 then return end
	if unit:getTotalHealth() <= unit:getAvailableHealth() then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h5/fx/Spells_Regeneration_Effect", "", 0.8, true)
	local amt, lvl = H5R.reviveHeal(unit, amount)
	if amt <= 0 then return end
	server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.oneBattle)
	server:refreshBattleUnits(battle)
end

return Script
