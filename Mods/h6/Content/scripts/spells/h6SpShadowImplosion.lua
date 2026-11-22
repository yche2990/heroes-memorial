--- Shadow Implosion (H6 class ability): the target enemy immediately takes pct% of the total damage over time remaining on it (Dark), then that damage over time is cleared.
--- Damage over time recognized: Agony, Mass Agony (combat/h6SpAgonyTick), poison and burning of H6 creatures (H6_DOT_H6C). Remaining ticks = remaining rounds - 1.
--- Parameters: pct (4 numbers), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local AGONY = nil
local function agonyKeys()
	if AGONY == nil then
		AGONY = {}
		for _, n in ipairs({ "heroes-memorial.h6:h6SpAgony", "heroes-memorial.h6:h6SpMassAgony" }) do
			local sp = LIBRARY:getSpellByName(n)
			if sp then AGONY[sp:getJsonKey()] = true end
		end
	end
	return AGONY
end

local function dots(u)
	local total = 0
	local keys = agonyKeys()
	local agony = u:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b) return keys[b:getSourceID()] == true end)
	for i = 1, agony:size() do local b = agony:getBonus(i); total = total + b:getVal() * math.max(1, b:getTurnsRemain() - 1) end
	local h6 = u:getBonuses({ type = "H6_DOT_H6C" })
	for i = 1, h6:size() do local b = h6:getBonus(i); total = total + b:getVal() * math.max(1, b:getTurnsRemain() - 1) end
	return total, agony, h6
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isAlive() or unit:getSide() == mechanics:getCasterSide() then return false end
	return (dots(unit)) > 0
end

function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local total, agony, h6 = dots(u)
	local d = S.spellDamage(mechanics, u, math.floor(total * S.pick(mechanics, self.pct) / 100), "02darkSchool")
	if Proxy.trial(server) then Proxy.damage(server, battle, u, d, { negative = true }); return end
	if agony:size() > 0 then Proxy.removeExact(server, battle, u, agony) end
	if h6:size() > 0 then Proxy.removeExact(server, battle, u, h6) end
	if d > 0 then
		L.show(server, battle, { u }, self.animation, self.sound)
		local _, killed = server:damageUnit(battle, u, d)
		if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
