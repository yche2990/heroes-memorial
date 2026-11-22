local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Champion Charge (H5 Champion)
--- When it moved at least minDistance hexes (default 2) before a melee attack, the enemy directly behind the target takes val% (default 50%) damage.
--- Parameters: minDistance, val

function Script:onBeforeMove(server, battle, unit) A.beforeMove(server, battle, unit) end
function Script:onAfterMove(server, battle, unit) A.afterMove(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other)
	if other ~= nil and other:unitID() == unit:unitID() then A.clearMove(server, battle, unit) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	if A.moved(unit) < (self.minDistance or 2) then return end
	local target = A.primary(payload, other)
	if target == nil then return end

	local from = A.nearestHex(unit, target)
	local to = A.nearestHex(target, unit)
	local n = A.hexDistance(from, to)
	if n == 0 then return end
	local hexes = A.hexTable(battle)
	local side = unit:getSide()
	-- Behind the target: the first hex past the target along the line "self -> target" (for a two-hex target its other hex is skipped)
	for k = n + 1, n + 2 do
		local idx = A.lineIndex(from, to, k)
		if idx == nil then return end
		local u = A.unitAt(battle, hexes, idx)
		if u ~= nil and u:unitID() ~= target:unitID() then
			if A.hostile(battle, unit, u) and A.damageable(u) then
				A.hit(server, battle, u, A.attackDamage(server, unit, u, self.val or 50, false), nil, nil)
			end
			return
		end
	end
end

return Script
