local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Life Drain (H6 Lich Master)
---
--- After the Lich Master casts "Life Drain" (does not use its action) it carries H6_LIFE_DRAIN_H6C this round: meanwhile, of the damage its attacks (counterattacks included) deal to living creatures,
--- pct% heals the most wounded other undead stack on its side (not itself; can resurrect, permanent).
--- Parameters: pct, animation, sound

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or not unit:hasBonuses({ type = "H6_LIFE_DRAIN_H6C" }) then return end
	local sum = 0
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and battle:isHostile(unit, t.unit) and L.isLiving(t.unit) then sum = sum + (t.damage or 0) end
	end
	local amount = math.floor(sum * (self.pct or 50) / 100)
	if amount <= 0 then return end
	local best, lost = nil, 0
	local list = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and u:unitID() ~= unit:unitID()
			and not battle:isHostile(unit, u) and L.isUndead(u)
	end)
	for _, u in ipairs(list) do
		local l = u:getTotalHealth() - u:getAvailableHealth()
		if l > lost then best, lost = u, l end
	end
	if best == nil then return end
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = best } }, self.animation, self.sound or "", 1.0, true)
	end
	local amt, lvl = L.reviveHeal(best, math.min(amount, lost))   -- Ring of Oblivion
	local healed, raised = server:healUnit(battle, best, amt, lvl, ENUM.HealPower.permanent)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_LIFE_DRAIN_H6C", 1, { L.name(unit), L.name(best) }, { healed or 0, raised or 0 })
end

return Script
