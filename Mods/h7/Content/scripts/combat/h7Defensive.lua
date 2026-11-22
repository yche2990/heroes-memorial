local Base = require("combat/combatScript")
local A = require("heroes-memorial.h7:combat/h7AuraLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Defensive Stance (Blackguard)
--- When it defends: unlimited counterattacks, and it cannot be flanked or attacked from behind (hidden marks H7_NO_FLANK_H7C value 1 and H7_VIGILANCE_H7C, read by backstab and flanking scripts), until its next action starts.

local KEY = "h7Defensive"

function Script:onDefend(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local src = unit:getCreature():getJsonKey()
	for _, t in ipairs({ "UNLIMITED_RETALIATIONS", "H7_NO_FLANK_H7C", "H7_VIGILANCE_H7C", "H7_DEFENSIVE_H7C" }) do
		A.removeByStacking(server, battle, unit, t, KEY)
	end
	local function add(t, v, hidden)
		server:addUnitBonus(battle, unit, {
			type = t, val = v, duration = ENUM.BonusDuration.stackGetsTurn,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = KEY, hidden = hidden
		}, true)
	end
	add("UNLIMITED_RETALIATIONS", 0, true)
	add("H7_NO_FLANK_H7C", 1, true)
	add("H7_VIGILANCE_H7C", 1, true) -- Read by Backstab (h7Backstab) of batch B
	add("H7_DEFENSIVE_H7C", 0, false)
	server:refreshBattleUnits(battle)
end

return Script
