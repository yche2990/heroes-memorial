--- Doom (H6 Memorial Sanctum, Necropolis Warcry): the target enemy core or elite stack (levels 1-6, bosses excepted) dies entirely after turns rounds, unless the battle ends first.
--- One round less per 10 points of hero Attack (original "-power"), at least 3 rounds. The target gets combat/h6MmDoomTick and a visible countdown (val = remaining rounds).
--- Parameters: turns (4 numbers), animation, sound, death (animation on death)
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not M.real(unit) or unit:getSide() == mechanics:getCasterSide() then return false end
	local lv = unit:creatureLevel()
	return lv >= 1 and lv <= 6
end
function Script:isReceptive(mechanics, unit) return M.receptive(mechanics, unit) end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local n = math.max(3, S.pick(mechanics, self.turns) - math.floor(M.attack(mechanics) / 10))
	if Proxy.trial(server) then Proxy.damage(server, battle, u, u:getAvailableHealth() * Proxy.controlRatio(8 / n, 1)); return end
	L.show(server, battle, { u }, self.animation, self.sound)
	L.removeByStacking(server, battle, u, "COMBAT_EVENT_TRIGGER", "h6MmDoom")
	L.removeByStacking(server, battle, u, "H6_MM_DOOM_H6C", "h6MmDoom")
	M.addOther(server, battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6MmDoomTick", val = 0, hidden = true, stacking = "h6MmDoom",
		addInfo = { animation = self.death or "", sound = self.deathSound or "" } })
	M.addOther(server, battle, u, { type = "H6_MM_DOOM_H6C", val = n, stacking = "h6MmDoom", icon = "h6/abilities/mm_Doom" })
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
