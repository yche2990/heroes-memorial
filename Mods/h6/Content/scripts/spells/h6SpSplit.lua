--- Word of Light, Curse of the Netherworld (H6 class abilities): one amount of damage split evenly among one kind of stacks, one amount of healing split evenly among another (no target to choose).
--- Parameters: dmgBase, dmgPer (4 numbers), dmgWho ("evilEnemy" enemy undead, demons and orcs / "living" all living stacks on the battlefield), school,
---       healBase, healPer (4 numbers, total healing), healFromDamage (this percentage of the actual damage is used for healing),
---       healWho ("livingAlly" friendly living stacks / "undead" all undead on the battlefield), animation, sound
local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function pick(battle, side, who)
	return battle:getUnitsIf(function(u)
		if not L.real(u) then return false end
		if who == "evilEnemy" then return u:getSide() ~= side and S.evil(u) end
		if who == "living" then return L.isLiving(u) end
		if who == "livingAlly" then return u:getSide() == side and L.isLiving(u) end
		if who == "undead" then return L.isUndead(u) end
		return false
	end)
end

function Script:applicableGeneral(mechanics, problem)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	if #pick(battle, side, self.dmgWho) == 0 then
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
	local victims = pick(battle, side, self.dmgWho)
	local dealt = 0
	if #victims > 0 then
		local each = math.floor(S.value(mechanics, self.dmgBase, self.dmgPer) / #victims)
		if not Proxy.trial(server) then L.show(server, battle, victims, self.animation, self.sound) end
		for _, u in ipairs(victims) do
			local d = S.spellDamage(mechanics, u, each, self.school)
			if Proxy.trial(server) then
				Proxy.damage(server, battle, u, d, { school = self.school, negative = true })
			elseif d > 0 then
				local before = u:getAvailableHealth()
				local _, killed = server:damageUnit(battle, u, d)
				dealt = dealt + math.max(0, before - u:getAvailableHealth())
				if server:describeChanges() then BattleLog.creaturesPerish(server, battle, u, killed) end
			end
		end
	end
	local total = math.floor(S.value(mechanics, self.healBase, self.healPer) + dealt * (self.healFromDamage or 0) / 100)
	local friends = (self.healWho and total > 0) and pick(battle, side, self.healWho) or {}
	if #friends > 0 and not Proxy.trial(server) then
		local each = math.floor(total / #friends)
		for _, u in ipairs(friends) do
			if each > 0 then server:healUnit(battle, u, each, ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
