local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Magic Attack (H5 Mage, Archmage, Battle Mage)
--- When shooting, every stack on the line of fire (between shooter and target, own stacks included) takes the same shot damage.
--- Eldritch Aura (H5_ELDRITCH_AURA_H5C, Battle Mage): stacks of the Battle Mage's side adjacent to it take no line damage (the Battle Mage itself still does).

local function eldritchProtected(battle, u)
	local side = u:getSide()
	local guards = battle:getUnitsIf(function(g)
		return g:isAlive() and not g:isGhost() and not battle:isHostile(g, u) and g:unitID() ~= u:unitID()
			and A.has(g, "H5_ELDRITCH_AURA_H5C")
	end)
	for _, g in ipairs(guards) do
		if A.unitDistance(g, u) == 1 then return true end
	end
	return false
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter then return end
	if not unit:isAlive() then return end
	local target = A.primary(payload, other)
	if target == nil then return end
	local from = A.nearestHex(unit, target)
	local to = A.nearestHex(target, unit)
	local n = A.hexDistance(from, to)
	if n <= 1 then return end
	local hexes = A.hexTable(battle)
	local seen = { [unit:unitID()] = true, [target:unitID()] = true }
	local victims = {}
	for k = 1, n - 1 do
		local idx = A.lineIndex(from, to, k)
		local u = idx and A.unitAt(battle, hexes, idx)
		if u ~= nil and not seen[u:unitID()] and A.damageable(u) then
			seen[u:unitID()] = true
			if not eldritchProtected(battle, u) then table.insert(victims, u) end
		end
	end
	for _, v in ipairs(victims) do
		if v:isAlive() then
			A.hit(server, battle, v, A.attackDamage(server, unit, v, 100, true), nil, nil)
		end
	end
end

return Script
