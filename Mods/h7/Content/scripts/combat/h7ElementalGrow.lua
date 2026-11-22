local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Summon Elemental (H7) Expert effect (put on the summoned stack by spells/h7SummonElemental):
--- at the start of each later round, if the stack is still alive its count + val (may exceed the summoned count; summons still vanish after battle).
--- Nothing is added in the round of summoning (onRoundStart triggers from the next round).

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local n = self.val or 0
	if n <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/sfSummonElemental", "h7/sf_summon_elemental.ogg", 0.8, true)
	server:healUnit(battle, unit, n * unit:getMaxHealth(), ENUM.HealLevel.overheal, ENUM.HealPower.oneBattle)
	server:refreshBattleUnits(battle)
end

return Script
