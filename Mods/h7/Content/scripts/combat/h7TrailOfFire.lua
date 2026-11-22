local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Trail of Fire (Blaze Dragon)
---
--- When this stack moves (plain moves or the move before an attack), it leaves a trail of fire along its path (the straight line from start to end, excluding the hexes where it stops),
--- lasting until the end of the next round: enemies standing on the path take val x own stack size Fire damage at once; afterwards enemies walking into the trail or acting while standing on it
--- (wait, defend, shoot, cast) take the same Fire damage (spell obstacle + triggering spell h7AbTrailOfFireFlames, Fire, enemies only).
--- Approximation: the path is a straight line (the Blaze Dragon flies; in H7 using the trail also makes it fly); "damage when standing in fire at round start" becomes
--- the engine's "triggered when acting on an obstacle".
---
--- Parameters: val (Fire damage per dragon, H7's 25 scaled to level 7 damage), turns (rounds of the trail, default 2)

local SPELL = "h7AbTrailOfFireFlames"
local ANIM = "h7/fx/h7TrailOfFireGround"
local FROM = "h7TrailFrom"

function Script:onBeforeMove(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local pos = unit:getPosition()
	if pos == nil or not pos:isValid() then return end
	L.setMark(server, battle, unit, FROM, L.hexIndex(pos) + 1, 1)
end

function Script:onAfterMove(server, battle, unit, other, payload)
	local from = L.markValue(unit, FROM)
	if from == nil then return end
	L.clearMark(server, battle, unit, FROM)
	if not unit:isAlive() then return end
	local hexes = L.hexTable(battle)
	local start = hexes[from - 1]
	local stop = unit:getPosition()
	if start == nil or stop == nil then return end
	local n = L.hexDistance(start, stop)
	if n <= 0 then return end

	local trail, victims, seen = {}, {}, {}
	for k = 0, n do
		local idx = (k == 0) and (from - 1) or L.lineIndex(start, stop, k)
		local h = idx and hexes[idx]
		if h ~= nil and not unit:coversPos(h) then
			table.insert(trail, h)
			local u = battle:getUnitByPos(h, true)
			if u ~= nil and not seen[u:unitID()] then
				seen[u:unitID()] = true
				if L.damageable(u) and battle:isHostile(unit, u) then table.insert(victims, u) end
			end
		end
	end
	if #trail == 0 then return end

	local power = (self.val or 13) * unit:getCount()
	for _, u in ipairs(victims) do
		local dmg = L.schoolDamage(u, power, "fire")
		if dmg > 0 and u:isAlive() then
			local dealt, killed = L.hit(server, battle, u, dmg, "h7/fx/h7FireImpact", "")
			L.log(server, battle, 13, { L.name(u) }, { dealt })
			L.perish(server, battle, u, killed)
		end
	end
	L.burnHexes(server, battle, unit, trail, SPELL, power, self.turns or 2, ANIM, ANIM .. "Appear")
	if #victims == 0 then server:refreshBattleUnits(battle) end
end

return Script
