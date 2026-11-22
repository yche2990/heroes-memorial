local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Fire Breath (Red Dragon, Blaze Dragon)
---
--- The engine's dragon breath (TWO_HEX_ATTACK_BREATH, a separate bonus on the creature) hits two hexes as usual. After its own melee attack (counterattacks and second strikes do not count):
---   · the hexes occupied by the stacks hit by this breath, and the breath's second hex (even if empty), catch fire until the end of the next round;
---   · enemies hit immediately take val x own stack size Fire damage (scaled by Fire reduction; Fire-immune stacks take none);
---   · afterwards enemies that walk into the fire or act while standing on it (wait, defend, shoot, cast) take the same Fire damage
---     (spell obstacle + triggering spell h7AbFireBreathFlames, Fire, enemies only).
--- Approximation: H7's "damage when standing in fire at round start" becomes the engine's "triggered when acting on an obstacle"; walking straight off the fire does no damage.
---
--- Parameters: val (Fire damage per dragon, H7's 40 scaled to level 7 damage), turns (rounds of fire, default 2)

local SPELL = "h7AbFireBreathFlames"
local ANIM = "h7/fx/h7FireBreathGround"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or (payload.attackIndex or 0) ~= 0 then return end
	if not unit:isAlive() then return end
	local main = payload.targets and payload.targets[1]
	local target = (main and main.unit) or other
	if target == nil then return end
	local power = (self.val or 20) * unit:getCount()

	local hexes = {}
	for _, e in ipairs(payload.targets or {}) do
		if e.unit then
			local hs = e.unit:getHexes()
			for i = 1, hs:size() do table.insert(hexes, hs:at(i)) end
		end
	end
	local from = L.nearestHex(unit, target)
	local to = L.nearestHex(target, unit)
	if from ~= nil and to ~= nil and L.hexDistance(from, to) == 1 then
		local idx = L.lineIndex(from, to, 2)
		local h = idx and L.hexTable(battle)[idx]
		if h ~= nil then table.insert(hexes, h) end
	end

	for _, e in ipairs(payload.targets or {}) do
		local u = e.unit
		if u ~= nil and L.damageable(u) and battle:isHostile(unit, u) then
			local dmg = L.schoolDamage(u, power, "fire")
			if dmg > 0 then
				local dealt, killed = L.hit(server, battle, u, dmg, "h7/fx/h7FireImpact", "")
				L.log(server, battle, 12, { L.name(u) }, { dealt })
				L.perish(server, battle, u, killed)
			end
		end
	end
	L.burnHexes(server, battle, unit, hexes, SPELL, power, self.turns or 2, ANIM, ANIM .. "Appear")
end

return Script
