local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Enrage (H6 Abyssal Worm, Enraged Kirin "Enrage", Michael "Wrath of Vengeance", Uriel "Holy Wrath")
---
--- The original grants an extra action every round, which the engine cannot do; instead, until the battle ends: extra attacks +attacks, Speed +speed, damage dealt +dmg%.
--- Trigger mode:
---   "hp"     health below pct% of its health at battle start (Abyssal Worm, Enraged Kirin)
---   "minion" all minions (creatures listed in minion) are dead (Michael)
---   "alone"  no other living stack on its side (Uriel: minions wiped out, nothing left to resurrect)
--- Parameters: mode, pct, minion (list of full creature names), attacks, speed, dmg, animation, sound

local KEY = "h6Enraged"

function Script:check(server, battle, unit)
	if not unit:isAlive() or L.markValue(unit, KEY) then return end
	local go = false
	if self.mode == "alone" then
		go = #battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and u:getSide() == unit:getSide() and u:unitID() ~= unit:unitID()
			and not u:isTurret() and not u:hasBonuses({ type = "SIEGE_WEAPON" }) end) == 0
	elseif self.mode == "minion" then
		local ids = {}
		for _, id in ipairs(self.minion or {}) do ids[id] = true end
		go = #L.friendsOfType(battle, unit:getSide(), ids, true) == 0
	else
		go = unit:getAvailableHealth() * 100 < L.initialHealth(unit) * (self.pct or 35)
	end
	if not go then return end
	L.setMark(server, battle, unit, KEY, 1)
	local src = unit:getCreature():getJsonKey()
	local function add(t, v, sub)
		local d = { type = t, val = v, duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Enrage" .. t }
		if sub then d.subtype = sub end
		server:addUnitBonus(battle, unit, d, true)
	end
	if (self.attacks or 1) > 0 then add("ADDITIONAL_ATTACK", self.attacks or 1) end
	if (self.speed or 5) > 0 then add("STACKS_SPEED", self.speed or 5) end
	if (self.dmg or 30) > 0 then add("GENERAL_DAMAGE_PREMY", self.dmg or 30) end
	add("H6_ENRAGED_H6C", 1)
	L.log(server, battle, "H6_ENRAGED_H6C", 1, { L.name(unit) }, {})
	L.show(server, battle, { unit }, self.animation, self.sound)
end

function Script:onAfterAttacked(server, battle, unit) self:check(server, battle, unit) end
function Script:onActionFinished(server, battle, unit) self:check(server, battle, unit) end
function Script:onRoundStart(server, battle, unit) self:check(server, battle, unit) end

return Script
