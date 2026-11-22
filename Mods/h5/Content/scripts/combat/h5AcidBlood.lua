local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Acid Blood (H5 Foul Hydra)
--- After being attacked in melee, acid blood sprays in a straight line in the direction "self -> attacker" (4 hexes from its side),
--- enemies on the line take val% (default 25%) of this stack's normal damage.
--- Parameter: val percent

local LENGTH = 4

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged then return end
	if other == nil or not unit:isAlive() or unit:isGhost() then return end
	local own = self:ownEntry(unit, payload)
	if own == nil or (own.damage or 0) <= 0 then return end

	local from = A.nearestHex(unit, other)
	local toward = A.nearestHex(other, unit)
	if A.hexDistance(from, toward) == 0 then return end

	local hexes = A.hexTable(battle)
	local side = unit:getSide()
	local seen, victims = {}, {}
	for k = 1, LENGTH do
		local idx = A.lineIndex(from, toward, k)
		if idx == nil then break end
		local u = A.unitAt(battle, hexes, idx)
		if u ~= nil and not seen[u:unitID()] and u:unitID() ~= unit:unitID() and A.hostile(battle, unit, u) and A.damageable(u) then
			seen[u:unitID()] = true
			table.insert(victims, u)
		end
	end

	local pct = self.val or 25
	for _, v in ipairs(victims) do
		if v:isAlive() then
			A.hit(server, battle, v, A.attackDamage(server, unit, v, pct, false), "C0ACID", "ACID")
		end
	end
end

return Script
