--- Wrath of the Sky Father (H6 class ability): every stack in the enemy deployment zone (the two outermost columns on the enemy side) takes base + per x Spell Power Air damage and is Dazed for 1 round.
--- Parameters: base, per (4 numbers), status, animation, sound
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function inZone(u, side)
	local hs = u:getHexes()
	for i = 1, hs:size() do
		local x = hs:at(i):getX()
		if side == ENUM.BattleSide.attacker then
			if x >= 14 then return true end
		elseif x <= 2 then return true end
	end
	return false
end

local function victims(battle, side)
	return battle:getUnitsIf(function(u) return L.real(u) and inZone(u, side) end)
end

function Script:applicableGeneral(mechanics, problem)
	if #victims(mechanics:getBattle(), mechanics:getCasterSide()) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end
function Script:transformTarget(mechanics, aimPoint, spellTarget) return spellTarget end
function Script:filterTarget(mechanics, target) return target end

function Script:apply(mechanics, server, target)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	local list = victims(battle, side)
	local raw = math.floor(S.value(mechanics, self.base, self.per))
	if not Proxy.trial(server) then L.show(server, battle, list, self.animation, self.sound) end
	for _, u in ipairs(list) do
		local d = S.spellDamage(mechanics, u, raw, "air")
		if Proxy.trial(server) then
			Proxy.damage(server, battle, u, d, { school = "air", negative = true })
		elseif d > 0 then
			local _, killed = server:damageUnit(battle, u, d)
			if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
		end
	end
	if not server:describeChanges() then return end
	local sp = self.status and LIBRARY:getSpellByName("kad-mechanics:" .. self.status) or nil
	if sp then
		for _, u in ipairs(list) do
			if u:isAlive() then
				local others = battle:getUnitsIf(function(x) return x:getSide() ~= u:getSide() and x:isAlive() and not x:isTurret() end)
				server:castSpell(battle, others[1] or u, sp, { u }, 0)
			end
		end
	end
	server:refreshBattleUnits(battle)
end

return Script
