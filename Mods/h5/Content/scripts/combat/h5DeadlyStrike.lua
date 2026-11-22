local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Deadly Strike (Death Knight)
--- After an attack or retaliation hits, it triggers with val% chance (raised by Deduction): the target also takes "total health before the hit x share%" minus the damage this hit already dealt
--- (so this hit takes away share% of the total health before the hit in all; the original description says "the damage dealt is half of the enemy's total HP"), ignoring Attack and Defense. Parameters: val, share

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local entry = H5.firstTarget(payload)
	if entry == nil or entry.unit == nil then return end
	local t = entry.unit
	if not t:isAlive() or t:isInvincible() or not battle:isHostile(unit, t) then return end
	if t:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
	local chance = math.min(100, math.floor((self.val or 25) * (100 + H5.boost(unit)) / 100))
	if not H5.roll(server, battle, unit, chance) then return end
	local total = math.floor((entry.healthBeforeAttack or t:getAvailableHealth()) * (self.share or 50) / 100)
	local extra = total - (entry.damage or 0)
	if extra <= 0 then return end
	local dealt, killed = server:damageUnit(battle, t, extra)
	H5.log(server, battle, "core.bonus.H5_MARK_H5C.description.12", { H5.name(unit) }, { dealt })
	BattleLog.creaturesPerish(server, battle, t, killed)
end

return Script
