--- Heroes IV Memorial: Life Drain. Rules as the engine's combat/lifeDrain (called directly).
--- Checked frame by frame against recordings in round 575: the Heroes IV vampire's drain is only the vampire's own attack animation (body turns purple, a blue energy stream in its hand, already in the creature's attack animation);
--- no extra effect is played on the target or the vampire, only the Drain Life sound. So the engine's SP06_ is replaced by an empty animation plus the Heroes IV Drain Life sound.
local Core = require("combat/lifeDrain")
local Fx = require("heroes-memorial.h4:combat/h4FxCore")
local Script = setmetatable({}, {__index = Core})
Script.__index = Script

function Script:onAfterAttack(server, battle, unit, other, payload)
	local proxy = Fx.proxy(server, function(b, targets, anim, sound, transparency, deferred)
		return server:showBattleAnimation(b, targets, "h4/fx/blank", "h4/spells/life_drain", 1.0, deferred)
	end)
	-- Ring of Oblivion (hota.artifacts): its patch only applies to core:lifeDrain, and this requires the original script, so the same restriction is applied here:
	-- with the ring, draining only heals up to full health and does not resurrect (round 587)
	local okRing, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	if okRing and ring then
		local inner = proxy
		proxy = setmetatable({}, { __index = function(_, k)
			if k == "healUnit" then
				return function(_, b, u, amount, level, power)
					local cap = math.max(0, u:getMaxHealth() - u:getFirstHPleft())
					return inner:healUnit(b, u, math.min(amount, cap), level, power)
				end
			end
			return inner[k]
		end })
	end
	return Core.onAfterAttack(self, proxy, battle, unit, other, payload)
end

return Script
