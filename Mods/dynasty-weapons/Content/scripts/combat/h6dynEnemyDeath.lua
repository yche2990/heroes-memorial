--- H6 Dynasty Weapon, Blade of Vengeance level 4 "Dust to Dust": in H6 the hero's Might +2 for each enemy stack wiped out.
--- Approximation: the script is on enemy stacks (the weapon gives BATTLE_WIDE + OPPOSITE_SIDE); when an enemy stack is wiped out, all living stacks of the other side (the weapon owner's) get Attack +val (cumulative this battle).
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Clones, arrow towers, war machines and summoned creatures being wiped out do not count; the bonus is not given to war machines either (they do not melee, so Attack means nothing).
--- Only one per stacking group counts: read the old value, remove it, add back the total (Lib.addTotal), so after the second wipe-out Attack is +2.
function Script:onDeath(server, battle, unit, other, payload)
	if unit:isClone() or unit:isTurret() or Lib.isSiege(unit) or Lib.isSummoned(unit) then return end
	local side = Lib.opposite(unit:getSide())
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() and not Lib.isSiege(x) end)) do
		Lib.addTotal(server, battle, u, {
			type = "PRIMARY_SKILL", subtype = "primarySkill.attack", val = self.val or 1,
			duration = "ONE_BATTLE", sourceType = "OTHER",
			description = self.text and ("@" .. self.text) or nil, icon = self.icon
		}, "h6dynAshes")
	end
end

return Script
