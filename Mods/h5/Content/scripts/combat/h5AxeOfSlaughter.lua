local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Axe of Slaughter (Pit Spawn)
--- After an attack or retaliation hits an enemy, the target takes extra "val x the target's count before the hit" damage (ignoring Attack and Defense). Parameter: val

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	local t = entry.unit
	if not t:isAlive() or t:isInvincible() or not battle:isHostile(unit, t) then return end
	local before = t:getCount() + (entry.killed or 0)
	local amount = (self.val or 2) * before
	if amount <= 0 then return end
	local dealt, killed = server:damageUnit(battle, t, amount)
	H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.10", { H5.name(unit) }, { dealt })
	BattleLog.creaturesPerish(server, battle, t, killed)
end

return Script
