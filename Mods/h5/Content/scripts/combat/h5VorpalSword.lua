local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Vorpal Sword (Pit Lord): each attack or retaliation kills at least val creatures of the target (val default 1).
--- After the hit, count how many were killed; if not enough, add damage to make up the difference (ignoring Attack and Defense).

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	local t = entry.unit
	if not t:isAlive() or t:isInvincible() or not battle:isHostile(unit, t) then return end
	local need = (self.val or 1) - (entry.killed or 0)
	if need <= 0 then return end
	local amount = t:getFirstHPleft() + (need - 1) * t:getMaxHealth()
	local dealt, killed = server:damageUnit(battle, t, amount)
	H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.11", { H5.name(unit) }, { killed })
	BattleLog.creaturesPerish(server, battle, t, killed)
end

return Script
