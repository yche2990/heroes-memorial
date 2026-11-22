local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Piercing Shot (Marksman; the Apprentice and Mage Disciple use combat/h7PiercingShotApprentice, Fire)
---
--- On its own shot (counter-shots do not count), a line is drawn from the shooter through the target to the edge of the battlefield, and every stack on the line besides the main target
--- (friend or foe, war machines included, arrow towers and invincible stacks excluded) also takes one shot's damage: each computed by the normal formula with its own Defense,
--- halved as well with the range penalty. fire = true makes it Fire: scaled by Fire reduction, Fire-immune stacks take none.
--- Approximation: the main target is settled by the engine as usual (physical); pierced damage ignores Luck; there is no arrow path, only a hit effect on each pierced stack.
---
--- Parameter: fire (Fire)

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter then return end
	if not unit:isAlive() or unit:isTurret() then return end
	if unit:hasBonuses({ type = "H7_NOVA_ARMED_H7C" }) then return end   -- A charged Magic Nova of the Mage Disciple no longer pierces
	local main = payload.targets and payload.targets[1]
	local target = (main and main.unit) or other
	if target == nil then return end
	local from, to = unit:getPosition(), target:getPosition()
	if from == nil or to == nil or not from:isValid() or not to:isValid() then return end
	local n = L.hexDistance(from, to)
	if n <= 0 then return end

	local half = false
	pcall(function() half = battle:hasDistancePenalty(unit, target) end)
	local hexes = L.hexTable(battle)
	local seen = { [unit:unitID()] = true, [target:unitID()] = true }
	local hit = {}
	for k = 1, n + 20 do
		local idx = L.lineIndex(from, to, k)
		if idx == nil then break end
		local h = hexes[idx]
		if h ~= nil then
			local u = battle:getUnitByPos(h, true)
			if u ~= nil and not seen[u:unitID()] and L.damageable(u) then
				seen[u:unitID()] = true
				table.insert(hit, u)
			end
		end
	end
	if #hit == 0 then return end

	local fire = self.fire == true
	for _, u in ipairs(hit) do
		if u:isAlive() then
			local dmg = L.attackDamage(server, unit, u, half and 50 or 100, true)
			if fire then dmg = L.schoolDamage(u, dmg, "fire") end
			if dmg > 0 then
				local dealt, killed = L.hit(server, battle, u, dmg, fire and "h7/fx/h7FireImpact" or "h7/fx/h7PiercingBeam", "")
				L.log(server, battle, 3, { L.name(unit), L.name(u) }, { dealt })
				L.perish(server, battle, u, killed)
			end
		end
	end
end

return Script
