local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Storm Strike (H5 Thane, Thunder Thane)
--- After an active melee hit, lightning jumps from the target to adjacent enemies, and on from there to their adjacent enemies, until there are no new enemies;
--- each enemy reached takes damage equal to this hit's damage to the target x val% (default 100%) (non-magical, not affected by magic resistance).
--- Air-immune enemies (SPELL_SCHOOL_IMMUNITY air / any) are not reached, and the lightning does not chain on through them (original: Storm Strike doesn't work on enemies with Air Immunity).
--- Parameter: val

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local target, entry = A.primary(payload, other)
	if target == nil or entry == nil then return end
	local damage = math.floor((entry.damage or 0) * (self.val or 100) / 100)
	if damage <= 0 then return end
	local side = unit:getSide()
	local visited = { [target:unitID()] = true }
	local frontier = { target }
	while #frontier > 0 do
		local cur = table.remove(frontier, 1)
		local nxt = battle:getUnitsIf(function(u)
			return not visited[u:unitID()] and A.hostile(battle, unit, u) and A.damageable(u) and not A.schoolImmune(u, "air") and A.unitDistance(u, cur) == 1
		end)
		table.sort(nxt, function(a, b) return a:unitID() < b:unitID() end)
		for _, u in ipairs(nxt) do
			visited[u:unitID()] = true
			A.hit(server, battle, u, damage, "h5/fx/Spells_ChainLightningHit", "LIGHTBLT")
			table.insert(frontier, u)
		end
	end
end

return Script
