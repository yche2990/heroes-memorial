local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Assault (H6 Crusher): after its own melee attack (after the enemy counterattack), chance% to strike the same target again,
--- with normal attack damage (H3 formula) and no counterattack. Parameters: chance, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload.isCounter or payload.ranged or (payload.attackIndex or 0) > 0 or not unit:isAlive() then return end
	local target = nil
	for _, t in ipairs(payload.targets or {}) do if t.unit then target = t.unit; break end end
	if target == nil or not L.real(target) or not battle:isHostile(unit, target) then return end
	if server:rngInt(1, 100) > L.chance(unit, self.chance or 25) then return end   -- Divination raises the chance
	local dealt, killed = L.hit(server, battle, target, L.attackDamage(server, unit, target, 100, false), self.animation, self.sound)
	L.log(server, battle, "H6_ASSAULT_H6C", 1, { L.name(unit), L.name(target) }, { dealt or 0, killed or 0 })
end

return Script
