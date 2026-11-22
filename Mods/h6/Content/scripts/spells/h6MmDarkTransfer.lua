--- Dark Transfer (H6 Memorial Sanctum, Dungeon Might): the target friendly stack gets Speed +99 until it starts acting (the engine removes it then; movement distance unchanged):
--- if it has not acted this round it acts right next, if it has, it acts first next round. The original also "sacrifices the current stack's action"; the engine cannot get the currently acting stack, so that part is not done.
--- Parameters: speed, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	if Proxy.trial(server) then Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_PREMY", val = 15, turns = 1 }); return end
	L.show(server, battle, { u }, self.animation, self.sound)
	L.removeByStacking(server, battle, u, "STACKS_SPEED", "h6MmDarkTransfer")
	server:addUnitBonus(battle, u, { type = "STACKS_SPEED", val = self.speed or 99, duration = ENUM.BonusDuration.stackGetsTurn,
		sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = "h6MmDarkTransfer",
		hidden = true }, false)
	L.removeByStacking(server, battle, u, "H6_MM_TRANSFER_H6C", "h6MmDarkTransfer")
	server:addUnitBonus(battle, u, { type = "H6_MM_TRANSFER_H6C", val = 1, duration = ENUM.BonusDuration.stackGetsTurn,
		sourceType = ENUM.BonusSource.other, sourceID = u:getCreature():getJsonKey(), stacking = "h6MmDarkTransfer", icon = "h6/abilities/mm_DarkTransfer" }, false)
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
