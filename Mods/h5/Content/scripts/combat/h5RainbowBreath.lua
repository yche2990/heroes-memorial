local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Rainbow Breath (H5 Crystal Dragon)
--- On an active melee attack, each enemy within r hexes behind the target along the attack direction takes one normal hit (each calculated separately).
--- r = round[(1 + random 1-10 + Luck) / 2], limited to 1 - maxRadius (default 5).
--- Parameter: maxRadius

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local target = A.primary(payload, other)
	if target == nil then return end
	local luck = 0
	pcall(function() luck = unit:getLuck() end)
	local r = math.floor((1 + server:rngInt(1, 10) + luck) / 2 + 0.5)
	r = math.max(1, math.min(self.maxRadius or 5, r))
	local from = A.nearestHex(unit, target)
	local to = A.nearestHex(target, unit)
	local n = A.hexDistance(from, to)
	if n == 0 then return end
	local hexes = A.hexTable(battle)
	local side = unit:getSide()
	local seen, victims = { [target:unitID()] = true }, {}
	for k = n + 1, n + r + 1 do
		local idx = A.lineIndex(from, to, k)
		if idx == nil then break end
		local u = A.unitAt(battle, hexes, idx)
		if u ~= nil and not seen[u:unitID()] and A.hostile(battle, unit, u) and A.damageable(u) then
			seen[u:unitID()] = true
			table.insert(victims, u)
		end
	end
	for _, v in ipairs(victims) do
		if v:isAlive() then
			A.hit(server, battle, v, A.attackDamage(server, unit, v, 100, false), nil, nil)
		end
	end
end

return Script
