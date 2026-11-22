local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Pack Hunter (H5 Wolf)
--- On an active melee attack, other own stacks of the same kind (also with Pack Hunter) adjacent to the target pounce too, each dealing one normal hit (no retaliation).

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	local target = A.primary(payload, other)
	if target == nil or not A.damageable(target) then return end
	if not battle:isHostile(unit, target) then return end   -- Round 375: no pack hunting when the target is an ally (when berserk or hypnotized)
	local side = unit:getSide()
	local pack = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not battle:isHostile(u, unit) and u:unitID() ~= unit:unitID()
			and not u:hasBonuses({ type = "NOT_ACTIVE" }) and A.ability(u, "h5PackHunter") ~= nil
			and A.unitDistance(u, target) == 1
	end)
	table.sort(pack, function(a, b) return a:unitID() < b:unitID() end)
	for _, w in ipairs(pack) do
		if not target:isAlive() then return end
		A.hit(server, battle, target, A.attackDamage(server, w, target, 100, false), nil, nil)
	end
end

return Script
