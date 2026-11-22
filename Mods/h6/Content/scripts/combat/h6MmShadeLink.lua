--- Entangling Shade (H6 Memorial Sanctum, Dungeon): when the original stack is wiped out, its illusion (val = illusion stack id) disappears and the illusion's aura is removed too.
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onDeath(server, battle, unit, other, payload)
	if unit:isAlive() then return end
	local id = self.val
	local list = battle:getUnitsIf(function(x) return x:unitID() == id and x:isAlive() end)
	for _, s in ipairs(list) do
		local key = "h6MmShadeAura" .. tostring(id)
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() end)) do L.removeByStacking(server, battle, u, "GENERAL_DAMAGE_PREMY", key); L.removeByStacking(server, battle, u, "H6_MM_SHADED_H6C", key) end
		L.removeByStacking(server, battle, s, "H6_MM_SHADE_H6C", "h6MmShade")
		L.log(server, battle, "H6_MM_STATUS_H6C", 5, { L.name(s) }, {})
		server:removeUnit(battle, s)
	end
	server:refreshBattleUnits(battle)
end

return Script
