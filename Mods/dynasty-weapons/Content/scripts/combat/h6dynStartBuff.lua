--- H6 Dynasty Weapons: bonuses attached to stacks at battle start (Prepare to Board, Grounded, Dual Discipline...).
--- The weapon gives the hero this COMBAT_EVENT_TRIGGER: attached directly for own stacks, with BATTLE_WIDE + OPPOSITE_SIDE for enemy ones.
--- Parameters: bonuses { name = bonus } (json form, turns = duration), flyers / walkers (only flying / non-flying stacks), anim
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() or unit:isTurret() then return end
	local flying = unit:hasBonuses({ type = "FLYING" })
	if self.flyers and not flying then return end
	if self.walkers and flying then return end
	for _, b in pairs(self.bonuses or {}) do
		Lib.addBonus(server, battle, unit, b, "OTHER", nil, false, Lib.textOf(self))
	end
	if Lib.anim(server, battle, unit, self.anim) then server:refreshBattleUnits(battle) end
end

return Script
