local Base = require("combat/combatScript")
local R = require("heroes-memorial.h7:combat/h7BloodRageLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Memorial Sanctum, Father Sky's Fury (Stronghold ultimate Father Sky's Fury, original values, Yu's decision 2026-11-01).
--- Linked to the H7 memorial Blood Rage (h7BloodRage.lua, no longer to the Tears of Ashan Blood Rage):
---   Blood Rage +2 at battle start: added by h7BloodRage.lua at battle start together with H7_SKYFURY_H7C passed down from the hero;
---   each time a stack on the battlefield is wiped out (either side, clones excluded): Blood Rage +2 for the side with Father Sky's Fury (it rises again even from 0).
--- Setup (gen_h7sanctum.py): the hero's hidden mark H7_SKYFURY_H7C is passed to its stacks; this script's carrier is passed BATTLE_WIDE to all stacks of both sides,
--- so every death triggers onDeath; if both heroes have it, the carriers share a stacking group and only one is kept, so nothing is added twice.

local MARK = "H7_SKYFURY_H7C"

local function furySide(battle, side)
	local list = battle:getUnitsIf(function(u) return u:getSide() == side and R.isRager(u) and u:hasBonuses({ type = MARK }) end)
	return #list > 0
end

function Script:onDeath(server, battle, unit, other, payload)
	if unit:isClone() then return end
	local any = false
	for side = 0, 1 do
		if furySide(battle, side) then
			R.setSide(server, battle, side, R.sideValue(battle, side) + 2)
			any = true
		end
	end
	if any then
		server:appendLog(battle, {
			append = { "core.bonus.H7_SANCTUM_H7C.description.4" },
			replaceStrings = { unit:getCreature():getNameTextID(2) },
			replaceNumbers = {}
		})
	end
end

return Script
