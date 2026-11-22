local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Vigilance (H6 Centaur, Centaur Marauder)
---
--- Hidden battle-wide bonus (BATTLE_WIDE): after an enemy moves, if it stops within range hexes of a Centaur with Vigilance (H6_VIGILANT_H6C)
--- (range without distance penalty), that Centaur automatically shoots it once (normal shot damage, uses no ammunition).
--- Each Centaur shoots each enemy stack only once per battle. A Centaur with an adjacent enemy does not shoot. Parameters: range, animation, sound

function Script:onAfterMove(server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	local scouts = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and battle:isHostile(unit, u) and u:hasBonuses({ type = "H6_VIGILANT_H6C" })
	end)
	for _, c in ipairs(scouts) do
		local key = "h6Vig" .. tostring(c:unitID())
		if unit:isAlive() and L.markValue(unit, key) == nil and L.unitDistance(c, unit) <= (self.range or 10) then
			local blocked = #L.around(battle, c, function(u) return battle:isHostile(c, u) end) > 0
			if not blocked then
				L.setMark(server, battle, unit, key, 1)
				local dealt = L.hit(server, battle, unit, L.attackDamage(server, c, unit, 100, true), self.animation, self.sound)
				L.log(server, battle, "H6_VIGILANT_H6C", 1, { L.name(c), L.name(unit) }, { dealt or 0 })
			end
		end
	end
end

return Script
