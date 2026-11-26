--- Unfettered (H6 Memorial Sanctum, Stronghold Warcry): dispels from all friendly stacks the negative spells that lower Speed, Morale, Attack or damage (the whole spell is removed).
--- Parameters: animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local M = require("lib/h6MmLib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local TYPES = { "STACKS_SPEED", "MORALE", "PRIMARY_SKILL", "GENERAL_DAMAGE_PREMY", "PERCENTAGE_DAMAGE_BOOST", "CREATURE_DAMAGE", "NOT_ACTIVE", "BIND_EFFECT" }

local function bad(u)
	local keys, n = {}, 0
	for _, t in ipairs(TYPES) do
		local list = u:getBonuses({ type = t, sourceType = ENUM.BonusSource.spellEffect })
		for i = 1, list:size() do
			local b = list:getBonus(i)
			local neg = b:getVal() < 0 or t == "NOT_ACTIVE" or t == "BIND_EFFECT"
			if t == "PRIMARY_SKILL" then neg = neg and tostring(b:getSubtype() or ""):find("attack", 1, true) ~= nil end
			if neg and not keys[b:getSourceID()] then keys[b:getSourceID()] = true; n = n + 1 end
		end
	end
	return keys, n
end

function Script:isValidTarget(mechanics, unit)
	return M.real(unit) and unit:getSide() == mechanics:getCasterSide()
end
function Script:isReceptive(mechanics, unit) return true end

function Script:applicableGeneral(mechanics, problem)
	local side = mechanics:getCasterSide()
	if #mechanics:getBattle():getUnitsIf(function(u) return M.real(u) and u:getSide() == side and select(2, bad(u)) > 0 end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local units = {}
	for _, dest in ipairs(target) do if dest.unit and M.real(dest.unit) then units[#units + 1] = dest.unit end end
	if Proxy.trial(server) then
		for _, u in ipairs(units) do
			local _, n = bad(u)
			if n > 0 then Proxy.buff(server, battle, u, { type = "GENERAL_DAMAGE_PREMY", val = 10 * n, turns = 2 }) end
		end
		return
	end
	local hit = {}
	for _, u in ipairs(units) do
		local keys, n = bad(u)
		if n > 0 then
			for k in pairs(keys) do S.removeSpell(server, battle, u, k) end
			hit[#hit + 1] = u
		end
	end
	L.show(server, battle, hit, self.animation, self.sound)
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
