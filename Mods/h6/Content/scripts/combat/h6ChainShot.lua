local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Electrocute (H6 Air Elemental): after a shot hits, lightning jumps from the target to the nearest jumps other enemy stacks (default 3),
--- each jump dealing half the previous one (starting from this shot's damage), scaled by Air reduction. Parameters: jumps, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter or not unit:isAlive() then return end
	local first, dmg = nil, 0
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and battle:isHostile(unit, t.unit) and (t.damage or 0) > 0 then first, dmg = t.unit, t.damage; break end
	end
	if first == nil then return end
	local hitIds = { [first:unitID()] = true }
	local from = first
	for _ = 1, (self.jumps or 3) do
		dmg = math.floor(dmg / 2)
		if dmg <= 0 then break end
		local best, bd = nil, 1000
		for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(unit, u) and not hitIds[u:unitID()] and not u:isInvincible() end)) do
			local d = L.unitDistance(from, u)
			if d < bd then best, bd = u, d end
		end
		if best == nil then break end
		hitIds[best:unitID()] = true
		L.hit(server, battle, best, math.floor(dmg * (100 - L.schoolReduction(best, "air")) / 100), self.animation, self.sound)
		from = best
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
