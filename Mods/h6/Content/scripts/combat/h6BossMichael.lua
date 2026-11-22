local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Devotion (H6 Michael): pct% of the damage Michael takes is passed to a living guard (minion): Michael regains that much health and the guard takes the same damage.
--- Parameters: pct, minion (list of full creature names), animation, sound

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local e = self:ownEntry(unit, payload)
	local dmg = e and e.damage or 0
	if dmg <= 0 then return end
	local ids = {}
	for _, id in ipairs(self.minion or {}) do ids[id] = true end
	local guards = L.friendsOfType(battle, unit:getSide(), ids, true)
	if #guards == 0 then return end
	local share = math.floor(dmg * (self.pct or 10) / 100)
	if share <= 0 then return end
	local g = guards[server:rngInt(1, #guards)]
	server:healUnit(battle, unit, share, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	L.rawHit(server, battle, g, share, self.animation, self.sound)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
