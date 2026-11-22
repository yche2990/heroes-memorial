local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ride-by Attack (H5 Brisk Raider)
--- On a melee attack after moving, enemies adjacent to the charge route (straight line from start to end, the last hex excluded), the main target excepted,
--- each take val% (default 25%) of this stack's normal damage.
--- Parameter: val

local EXCLUDE_LAST = 1

function Script:onBeforeMove(server, battle, unit) A.beforeMove(server, battle, unit) end
function Script:onAfterMove(server, battle, unit) A.afterMove(server, battle, unit) end

function Script:onActionFinished(server, battle, unit, other)
	if other ~= nil and other:unitID() == unit:unitID() then A.clearMove(server, battle, unit) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local start = A.movedFrom(battle, unit)
	local finish = unit:getPosition()
	if start == nil or finish == nil then return end
	local n = A.hexDistance(start, finish)
	if n <= EXCLUDE_LAST then return end
	local target = A.primary(payload, other)
	local hexes = A.hexTable(battle)
	local path = {}
	for k = 0, n - EXCLUDE_LAST do
		local idx = A.lineIndex(start, finish, k)
		if idx ~= nil and hexes[idx] ~= nil then table.insert(path, hexes[idx]) end
	end
	local side = unit:getSide()
	local victims = battle:getUnitsIf(function(u)
		if not (A.hostile(battle, unit, u) and A.damageable(u)) then return false end
		if target ~= nil and u:unitID() == target:unitID() then return false end
		for _, h in ipairs(path) do
			if A.unitHexDistance(u, h) == 1 then return true end
		end
		return false
	end)
	table.sort(victims, function(a, b) return a:unitID() < b:unitID() end)
	for _, v in ipairs(victims) do
		if v:isAlive() then
			A.hit(server, battle, v, A.attackDamage(server, unit, v, self.val or 25, false), nil, nil)
		end
	end
end

return Script
