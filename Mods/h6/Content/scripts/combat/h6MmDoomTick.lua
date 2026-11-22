--- Doom (H6 Memorial Sanctum, Necropolis) countdown: remaining rounds -1 at the start of each round; at 0 the whole stack dies (ignoring invincibility). Parameters: animation, sound
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local list = unit:getBonuses({ type = "H6_MM_DOOM_H6C" }):filter(function(b) return b:getStacking() == "h6MmDoom" end)
	if list:size() == 0 then return end
	local n = list:getBonus(1):getVal() - 1
	L.removeByStacking(server, battle, unit, "H6_MM_DOOM_H6C", "h6MmDoom")
	if n > 0 then
		server:addUnitBonus(battle, unit, { type = "H6_MM_DOOM_H6C", val = n, stacking = "h6MmDoom", duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), icon = "h6/abilities/mm_Doom" }, true)
		server:refreshBattleUnits(battle)
		return
	end
	L.removeByStacking(server, battle, unit, "COMBAT_EVENT_TRIGGER", "h6MmDoom")
	L.log(server, battle, "H6_MM_STATUS_H6C", 2, { L.name(unit) }, {})
	L.rawHit(server, battle, unit, unit:getAvailableHealth(), (self.animation ~= "" and self.animation) or nil, self.sound)
	server:refreshBattleUnits(battle)
end

return Script
