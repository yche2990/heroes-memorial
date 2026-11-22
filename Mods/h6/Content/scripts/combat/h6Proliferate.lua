local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Proliferate (H6 Breeder): stack size +pct% at battle start (rounded up); the extra creatures do not stay after battle. Parameters: pct, animation, sound

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() then return end
	local n = math.ceil(unit:getCount() * (self.pct or 20) / 100)
	if n <= 0 then return end
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = unit } }, self.animation, self.sound or "", 1.0, true)
	end
	local healed, raised = server:healUnit(battle, unit, n * unit:getMaxHealth(), ENUM.HealLevel.overheal, ENUM.HealPower.oneBattle)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_PROLIFERATE_H6C", 1, { L.name(unit) }, { raised or 0 })
end

return Script
