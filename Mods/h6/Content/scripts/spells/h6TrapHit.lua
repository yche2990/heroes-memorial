local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Crippling Trap sprung: the stack that steps on it takes physical damage equal to the strongest trap power (h6TrapPower) among its enemy Goblins.
--- Slowing is done by the timed effect of the same spell. Parameters: animation, sound

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local power = 0
			local list = battle:getUnitsIf(function(o) return o:isAlive() and battle:isHostile(o, u) and L.markValue(o, "h6TrapPower") ~= nil end)
			for _, o in ipairs(list) do power = math.max(power, L.markValue(o, "h6TrapPower")) end
			if power > 0 then
				local dealt = L.hit(server, battle, u, power, self.animation, self.sound)
				L.log(server, battle, "H6_TRAP_H6C", 1, { L.name(u) }, { dealt or 0 })
			end
		end
	end
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
