local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Mobile Shooter (Medusa Witch, Centaur Marauder), approximation
---
--- H7: may move and then shoot, or shoot and then move. The engine cannot let a stack shoot after moving in one turn,
--- and Lua cannot grant an extra action to "move after shooting" (newer engines dropped setMoved), so instead:
--- when this stack's own turn is only a move (no attack), after the move it automatically shoots the nearest enemy once: val% of normal shot damage,
--- halved with the range penalty, no Luck; no shot when blocked by an adjacent enemy or unable to shoot (no shooter ability or 100% Forgetful).
--- Approximation: the automatic shot has no shooting animation, no projectile and uses no ammunition, only a hit effect on the target before the damage; the target is the nearest enemy
--- (the one with more remaining health if equally near) and cannot be chosen by the player. The "move after shooting" half cannot be done.
---
--- Parameter: val (damage percentage, default 100)

local MOVED = "h7MsMoved"
local ATTACKED = "h7MsAttacked"

function Script:onAfterMove(server, battle, unit, other, payload)
	if unit:isAlive() then L.setMark(server, battle, unit, MOVED, 1, 1) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter then return end
	if unit:isAlive() then L.setMark(server, battle, unit, ATTACKED, 1, 1) end
end

function Script:onActionFinished(server, battle, unit, other, payload)
	local moved = L.markValue(unit, MOVED) ~= nil
	local attacked = L.markValue(unit, ATTACKED) ~= nil
	if moved then L.clearMark(server, battle, unit, MOVED) end
	if attacked then L.clearMark(server, battle, unit, ATTACKED) end
	if other == nil or other:unitID() ~= unit:unitID() then return end
	if not moved or attacked or not unit:isAlive() or unit:isClone() then return end
	if not L.canShoot(unit) or L.engaged(battle, unit) or unit:hasBonuses({ type = "NOT_ACTIVE" }) then return end

	local pos = unit:getPosition()
	local best, bestD, bestHp = nil, 1000, -1
	local enemies = battle:getUnitsIf(function(u)
		-- H7 audit A3: enemies inside a Mist Veil cannot be targeted by ranged attacks and are not chosen
		return L.damageable(u) and battle:isHostile(unit, u) and not u:hasBonuses({ type = "H7_FOGSHROUD_H7C" })
	end)
	for _, e in ipairs(enemies) do
		local d = L.unitHexDistance(e, pos)
		local hp = e:getAvailableHealth()
		if d < bestD or (d == bestD and hp > bestHp) then best, bestD, bestHp = e, d, hp end
	end
	if best == nil then return end

	local pct = self.val or 100
	local far = false
	pcall(function() far = battle:hasDistancePenalty(unit, best) end)
	if far then pct = pct / 2 end
	local dmg = L.attackDamage(server, unit, best, pct, true)
	if dmg <= 0 then return end
	local dealt, killed = L.hit(server, battle, best, dmg, "h7/fx/h7PiercingBeam", "")
	L.log(server, battle, 6, { L.name(unit), L.name(best) }, { dealt })
	L.perish(server, battle, best, killed)
end

return Script
