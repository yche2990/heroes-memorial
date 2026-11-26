--- Might of the Horde (H6 Memorial Sanctum, Stronghold Warcry): deals physical damage to the target enemy = current total health of the whole friendly army x pct% (unit 0.1%).
--- Physical damage: not affected by magic resistance or immunity. The original also adds a direct hero attack (not ported). Parameters: pct (4 numbers), animation, sound
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

function Script:amount(mechanics)
	local side = mechanics:getCasterSide()
	local total = 0
	for _, u in ipairs(mechanics:getBattle():getUnitsIf(function(u) return M.real(u) and u:getSide() == side and not u:isClone() end)) do
		total = total + u:getAvailableHealth()
	end
	return math.floor(total * S.pick(mechanics, self.pct) / 1000)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local u = target[1] and target[1].unit
	if u == nil or not u:isAlive() then return end
	local d = self:amount(mechanics)
	if Proxy.trial(server) then Proxy.damage(server, battle, u, d); return end
	L.show(server, battle, { u }, self.animation, self.sound)
	if d > 0 then
		local _, killed = server:damageUnit(battle, u, d)
		BattleLog.creaturesPerish(server, battle, u, killed)
	end
	server:refreshBattleUnits(battle)
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply. Current total health of the whole friendly army x pct per mille, physical damage (resistances not applied)
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local u = first and first.unit
		if u == nil or not u:isAlive() then return zero end
		local d = self:amount(mechanics)
		if d <= 0 then return zero end
		local copy = u:copy()
		local hp, cnt = copy:getAvailableHealth(), copy:getCount()
		copy:damage(d)
		return { hpDelta = -(hp - copy:getAvailableHealth()), unitsDelta = -(cnt - copy:getCount()) }
	end)
	if ok and result then return result end
	return zero
end

return Script
