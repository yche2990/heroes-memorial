local Base = require("combat/combatScript")
local C = require("heroes-memorial:combat/h5Common")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "Elrath's Touch" of Resurrection (H7): the spell h7Resurrection puts it on the allies adjacent to the target (healing once at cast time, then twice more at the start of each round),
--- each time restoring val health and able to resurrect the stack's dead creatures (permanent); with the Ring of Oblivion (HOTA_RING_OF_OBLIVION) no resurrection, only the top creature is healed.
--- Undead, non-living and mechanical stacks are excluded at cast time.
---
--- Parameters:
---   val   amount restored each time

local ANIM = "h7/fx/slElrathTouch"

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() then return end
	local amount = self.val or 0
	if amount <= 0 then return end
	if unit:getTotalHealth() <= unit:getAvailableHealth() then return end
	local amt, lvl = C.reviveHeal(unit, amount)
	if amt <= 0 then return end
	L.anim(server, battle, { unit }, ANIM, "", 0.85)
	local healed, raised = server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent)
	server:refreshBattleUnits(battle)
	if raised and raised > 0 then
		server:appendLog(battle, {
			append         = { raised == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
			replaceStrings = { unit:getCreature():getNameTextID(raised) },
			replaceNumbers = { raised }
		})
	end
end

return Script
