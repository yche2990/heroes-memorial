--- H6 memorial Gating: when the source stack is wiped out, the demons it gated in (val = id of the summoned stack) return to the Abyss. Parameters: fx, sound
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onDeath(server, battle, unit, other, payload)
	if unit:isAlive() then return end
	local id = self.val
	for _, s in ipairs(battle:getUnitsIf(function(x) return x:unitID() == id and x:isAlive() end)) do
		if self.fx and server:describeChanges() then server:showBattleAnimation(battle, { { unit = s } }, self.fx, self.sound or "", 1.0, false) end
		L.log(server, battle, "H6_MM_STATUS_H6C", 8, { L.name(s) }, {})
		server:removeUnit(battle, s)
	end
	server:refreshBattleUnits(battle)
end

return Script
