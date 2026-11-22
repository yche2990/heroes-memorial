--- Heroes IV Memorial: Phoenix rebirth. Rules as the engine's combat/rebirth, with the Heroes IV rebirth effect (firebird).
local Core = require("combat/rebirth")
local Fx = require("heroes-memorial.h4:combat/h4FxCore")
local Script = setmetatable({}, {__index = Core})
Script.__index = Script

function Script:onDeath(server, battle, unit, other, payload)
	local proxy = Fx.proxy(server, function(b, targets, anim, sound, transparency, deferred)
		return server:showBattleAnimation(b, targets, "h4/fx/rebirth", sound, 1.0, deferred)
	end)
	return Core.onDeath(self, proxy, battle, unit, other, payload)
end

return Script
