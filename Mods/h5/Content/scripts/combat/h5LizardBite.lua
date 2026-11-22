local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Lizard Bite (H5 Brisk Raider, Grim Raider)
--- When an ally actively attacks an enemy adjacent to this stack, this stack bites it too, for val% (default 50%) of its normal damage.
--- This script is only the ability itself (for display); settling is done by the hidden area script h5AreaZone on all stacks calling Script.onAllyAttack.
--- Parameter: val

function Script.onAllyAttack(server, battle, attacker, target, val)
	if target == nil or not A.damageable(target) then return end
	local side = attacker:getSide()
	local biters = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not battle:isHostile(u, attacker) and u:unitID() ~= attacker:unitID()
			and not u:hasBonuses({ type = "NOT_ACTIVE" }) and A.ability(u, "h5LizardBite") ~= nil
			and A.unitDistance(u, target) == 1
	end)
	table.sort(biters, function(a, b) return a:unitID() < b:unitID() end)
	for _, b in ipairs(biters) do
		if not target:isAlive() then return end
		local ab = A.ability(b, "h5LizardBite")
		local pct = (ab and ab:getVal() > 0) and ab:getVal() or (val or 50)
		A.hit(server, battle, target, A.attackDamage(server, b, target, pct, false), nil, nil)
	end
end

return Script
