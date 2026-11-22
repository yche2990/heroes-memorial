--- Blood of Fury (H6 Memorial Sanctum, Stronghold Warcry): the H6 Blood Rage level of the target friendly H6 Stronghold stack (H6_BLOODRAGE_H6C) +levels (at most IV),
--- duration +turns rounds (original "+2 rounds"; without Blood Rage it starts from level 0 and lasts turns rounds). Blood Rage effects: see lib/h6RcLib.setRage.
--- Yu's decision (round 418): it works on the H6 Blood Rage, not on Tears of Ashan Blood Rage. Parameters: levels, turns, animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local R = require("lib/h6RcLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide() and R.isRager(unit)   -- Can be cast at level IV too (only adds duration)
end
function Script:isReceptive(mechanics, unit) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local n, t = self.levels or 2, self.turns or 2
	if Proxy.trial(server) then Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_PREMY", val = 10 * n, turns = 3 }); return end
	local lv, turns = R.rageLevel(u)
	L.show(server, battle, { u }, self.animation, self.sound)
	R.setRage(server, battle, u, math.min(4, lv + n), math.max(t, (lv > 0 and turns or 0) + t))
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
