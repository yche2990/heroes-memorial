local Base = require("combat/combatScript")
local L = require("combat/h7StatusLib")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Fatal Strike (Soul Reaper)
---
--- When an attack (counterattacks included) damages the main target but kills none, the top creature's remaining health is dealt as well, so at least one dies.
--- Invincible targets are not affected.

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil then return end
	local entry = self:ownEntry(other, payload)
	if entry == nil or (entry.damage or 0) <= 0 or (entry.killed or 0) > 0 then return end
	if not L.canHit(battle, unit, other) then return end
	local hp = other:getFirstHPleft()
	if hp == nil or hp <= 0 then return end
	server:showBattleAnimation(battle, { { unit = other } }, "C07SPE0", "", 1.0, true)
	local name = L.name(other)
	local dealt, killed = server:damageUnit(battle, other, hp)
	L.log(server, battle, 10, { name }, { dealt })
	BattleLog.creaturesPerish(server, battle, other, killed)
end

return Script
