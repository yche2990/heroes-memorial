local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Wraith Dragon (H6 boss) and Channelers:
---   role = "dragon": Wave of Decay: at the start of each round, as long as one of its Channelers (minion) is alive, each enemy stack takes per Dark damage;
---                    Void Power: for every step health the Channelers healed this battle, damage dealt +bonus% (at most max%).
---   role = "channeler": at the start of each round (at most charges times per battle) heals its Wraith Dragon (boss) by heal x number of Channelers.
--- Parameters: role, per, minion, step, bonus, max, boss, heal, charges, animation, sound

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	if self.role == "channeler" then
		local used = L.markValue(unit, "h6Channel") or 0
		if used >= (self.charges or 10) then return end
		local ids = {}
		for _, id in ipairs(self.boss or {}) do ids[id] = true end
		local dragons = L.friendsOfType(battle, unit:getSide(), ids, true)
		local d = dragons[1]
		if d == nil or d:getAvailableHealth() >= L.initialHealth(d) then return end
		L.setMark(server, battle, unit, "h6Channel", used + 1)
		local healed = server:healUnit(battle, d, (self.heal or 11) * unit:getCount(), ENUM.HealLevel.heal, ENUM.HealPower.permanent) or 0
		local acc = (L.markValue(d, "h6VoidPower") or 0) + healed
		L.setMark(server, battle, d, "h6VoidPower", acc)
		L.show(server, battle, { d }, self.animation, self.sound)
		return
	end
	-- Wraith Dragon: first update Void Power from the total healing
	local acc = L.markValue(unit, "h6VoidPower") or 0
	local lv = math.min(self.max or 100, math.floor(acc / (self.step or 600)) * (self.bonus or 10))
	if lv > 0 then
		L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_PREMY", "h6VoidPower")
		server:addUnitBonus(battle, unit, { type = "GENERAL_DAMAGE_PREMY", val = lv, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = "h6VoidPower" }, true)
	end
	local ids = {}
	for _, id in ipairs(self.minion or {}) do ids[id] = true end
	if #L.friendsOfType(battle, unit:getSide(), ids, true) == 0 then return end
	local list = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(unit, u) and not u:isInvincible() end)
	local total = 0
	for _, u in ipairs(list) do
		total = total + (L.hit(server, battle, u, math.floor((self.per or 80) * (100 - L.schoolReduction(u, "02darkSchool")) / 100), self.animation, self.sound) or 0)
	end
	if #list > 0 then
		if server:describeChanges() then server:refreshBattleUnits(battle) end
		L.log(server, battle, "H6_AREA_H6C", 13, { L.name(unit) }, { #list, total })
	end
end

return Script
