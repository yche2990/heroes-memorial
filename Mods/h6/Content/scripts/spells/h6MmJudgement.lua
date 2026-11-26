--- Moment of Judgment (H6 Memorial Sanctum, Haven Warcry): this round all friendly stacks deal +pct% damage when attacking enemies with Anathema; the Anathema on an enemy disappears once it is hit.
--- How it works: every friendly stack gets combat/h6MmJudgementHit (1 round, source not a spell effect). Parameters: pct (4 numbers), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function cursed(battle, side)
	return battle:getUnitsIf(function(u) return M.real(u) and u:getSide() ~= side and M.cursed(u) end)
end

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:applicableGeneral(mechanics, problem)
	if #cursed(mechanics:getBattle(), mechanics:getCasterSide()) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return Base.applicableGeneral(self, mechanics, problem)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local p = S.pick(mechanics, self.pct)
	local units = {}
	for _, dest in ipairs(target) do if dest.unit and M.real(dest.unit) then units[#units + 1] = dest.unit end end
	if Proxy.trial(server) then
		for _, u in ipairs(units) do Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_PREMY", val = math.floor(p / 2), turns = 1 }) end
		return
	end
	L.show(server, battle, units, self.animation, self.sound)
	for _, u in ipairs(units) do
		L.removeByStacking(server, battle, u, "COMBAT_EVENT_TRIGGER", "h6MmJudgement")
		M.addOther(server, battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmJudgementHit", val = p, stacking = "h6MmJudgement",
			icon = "h6/abilities/mm_HourOfJudgement" }, 1)
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
