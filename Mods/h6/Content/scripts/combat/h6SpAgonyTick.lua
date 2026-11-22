--- Agony (H6): takes val Dark damage at the start of each round (Dark reduction and immunity as the Agony spell), living troops only. Parameter: spell (full spell name)
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() or not L.isLiving(unit) then return end
	local raw = self.val or 0
	if raw <= 0 then return end
	local sp = LIBRARY:getSpellByName(self.spell or "")
	local dmg = raw
	if sp then
		local side = unit:getSide()
		local foe = battle:getUnitsIf(function(x) return x:getSide() ~= side and x:isAlive() and not x:isTurret() end)[1]
		if foe then
			local ok, v = pcall(function() return sp:adjustDamage(battle, foe, unit, raw) end)
			if ok and v then dmg = v end
		end
	end
	if dmg > 0 then L.hit(server, battle, unit, dmg, self.animation, self.sound) end
end

return Script
