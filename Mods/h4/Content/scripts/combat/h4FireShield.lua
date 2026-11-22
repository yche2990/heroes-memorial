--- Heroes IV Memorial: Fire Shield. Rules as the engine's combat/fireShield, with the Heroes IV burning shield played on the burned attacker (as in original recordings).
local Core = require("combat/fireShield")
local Fx = require("heroes-memorial.h4:combat/h4FxCore")
local Script = setmetatable({}, {__index = Core})
Script.__index = Script

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local proxy = Fx.proxy(server, function(b, targets, anim, sound, transparency, deferred)
		return server:showBattleAnimation(b, { { unit = other } }, "h4/fx/fire_shield", sound, 1.0, deferred)
	end)
	return Core.onAfterAttacked(self, proxy, battle, unit, other, payload)
end

return Script
