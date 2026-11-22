local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Soul-Flaying Breath (Spectral Dragon)
---
--- H7: a 5-hex line of Dark breath, 100% on the first hex and 20% less for each hex further.
--- Here: the engine's dragon breath (TWO_HEX_ATTACK_BREATH, a separate bonus on the creature) hits hexes 1 and 2 as usual; after its own melee attack (counterattacks and second strikes do not count),
--- this script continues along the line "Spectral Dragon -> target" to the enemies on hexes 3-5 (those the engine already hit are skipped):
--- normal melee damage (Attack/Defense modifier applied) x 60% / 40% / 20%, then Dark reduction; Dark-immune stacks take none.
--- Approximation: hex 2 is settled by the engine at 100% physical damage (80% Dark in the original); the engine breath still burns allies on hex 2.
---
--- Parameters: range (hexes, default 5), step (reduction per hex in percent, default 20)

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local main = payload.targets and payload.targets[1]
	local target = (main and main.unit) or other
	if target == nil then return end

	local from = L.nearestHex(unit, target)
	local to = L.nearestHex(target, unit)
	if from == nil or to == nil or L.hexDistance(from, to) ~= 1 then return end

	local done = { [unit:unitID()] = true }
	for _, e in ipairs(payload.targets or {}) do
		if e.unit then done[e.unit:unitID()] = true end
	end

	local hexes = L.hexTable(battle)
	local range = self.range or 5
	local step = self.step or 20
	for k = 3, range do
		local idx = L.lineIndex(from, to, k)
		if idx == nil then break end
		local h = hexes[idx]
		local u = h and battle:getUnitByPos(h, true)
		if u ~= nil and not done[u:unitID()] then
			done[u:unitID()] = true
			if L.damageable(u) and battle:isHostile(unit, u) then
				local pct = 100 - step * (k - 1)
				if pct > 0 then
					local dmg = L.schoolDamage(u, L.attackDamage(server, unit, u, pct, false), "dark")
					if dmg > 0 then
						local dealt, killed = L.hit(server, battle, u, dmg, "h7/fx/h7DarkImpact", "")
						L.log(server, battle, 8, { L.name(unit), L.name(u) }, { dealt })
						L.perish(server, battle, u, killed)
					end
				end
			end
		end
	end
end

return Script
