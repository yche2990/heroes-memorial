--- Inferno (H6 class ability): the target enemy takes base + per x Spell Power Fire damage, then it jumps to the nearest other enemy within two hexes for the same damage.
--- Parameters: base, per (4 numbers), jumpRange (default 2), animation, sound
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:hit(mechanics, server, battle, u, raw)
	local d = S.spellDamage(mechanics, u, raw, "fire")
	if Proxy.trial(server) then Proxy.damage(server, battle, u, d, { school = "fire", negative = true }); return end
	if d <= 0 then return end
	L.show(server, battle, { u }, self.animation, self.sound)
	local _, killed = server:damageUnit(battle, u, d)
	if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local main = target[1] and target[1].unit
	if main == nil or not main:isAlive() then return end
	local raw = math.floor(S.value(mechanics, self.base, self.per))
	local side = main:getSide()
	local best, bestD = nil, 1000
	for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:getSide() == side and x:unitID() ~= main:unitID() end)) do
		local d = L.unitDistance(main, u)
		if d <= (self.jumpRange or 2) and d < bestD then best, bestD = u, d end
	end
	self:hit(mechanics, server, battle, main, raw)
	if best then self:hit(mechanics, server, battle, best, raw) end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply. The target and the nearest other stack of the same side within jumpRange hexes each take base + per x Spell Power fire damage
--- (through the engine's spell damage adjustment); the two are summed
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if main == nil or not main:isAlive() then return zero end
		local raw = math.floor(S.value(mechanics, self.base, self.per))
		local side = main:getSide()
		local best, bestD = nil, 1000
		for _, u in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:getSide() == side and x:unitID() ~= main:unitID() end)) do
			local d = L.unitDistance(main, u)
			if d <= (self.jumpRange or 2) and d < bestD then best, bestD = u, d end
		end
		local out = { hpDelta = 0, unitsDelta = 0 }
		local function one(u)
			local d = math.floor(S.spellDamage(mechanics, u, raw, "fire") or 0)
			if d <= 0 then return end
			local copy = u:copy()
			local hp, cnt = copy:getAvailableHealth(), copy:getCount()
			copy:damage(d)
			out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
			out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
		end
		one(main)
		if best then one(best) end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
