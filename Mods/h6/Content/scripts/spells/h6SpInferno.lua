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

return Script
