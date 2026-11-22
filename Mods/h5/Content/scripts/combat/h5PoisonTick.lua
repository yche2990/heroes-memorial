local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 poison, settling: attached to the target by combat/h5Poison, deals val damage at the start of each round (ignoring Attack and Defense).
--- Removed by the engine when its rounds run out.

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() or unit:isInvincible() then return end
	local amount = self.val or 0
	if amount <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h5/fx/Characters_hits_poison_hit", "", 0.8, true)
	local dealt, killed = server:damageUnit(battle, unit, amount)
	server:appendLog(battle, {
		append         = { "core.bonus.H5_MARK_H5C.description.6" },
		replaceStrings = { unit:getCreature():getNameTextID(2) },
		replaceNumbers = { dealt }
	})
	BattleLog.creaturesPerish(server, battle, unit, killed)
end

return Script
