--- Divine Justice (H6 Memorial Sanctum, Haven Warcry): the target enemy takes pct% of "the total damage its attacks have dealt so far this battle", at most cap. Counted as physical damage (not affected by magic resistance or immunity).
--- The total is recorded on the attacker (hidden mark h6MmDealt) by the battle-wide bookkeeping script combat/h6MmDmgTrack the hero carries after learning it.
--- Parameters: pct (4 numbers), cap (4 original caps, converted with h6MmLib.value), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() ~= mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return M.receptive(mechanics, unit) end

function Script:amount(mechanics, u)
	local dealt = L.markValue(u, "h6MmDealt") or 0
	return math.floor(math.min(dealt * S.pick(mechanics, self.pct) / 100, M.value(mechanics, self.cap)))
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local d = self:amount(mechanics, u)
	if Proxy.trial(server) then Proxy.damage(server, battle, u, d); return end
	L.show(server, battle, { u }, self.animation, self.sound)
	if d > 0 then
		local _, killed = server:damageUnit(battle, u, d)
		BattleLog.creaturesPerish(server, battle, u, killed)
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
