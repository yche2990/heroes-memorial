local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local SL = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shield from activating the Rune of Fortune (H7): put by h7RuneStone (mode = "activate", Rune Stone of Fortune) on allies in the aura; val = damage it can still absorb.
--- Attacks taken (melee, ranged, counterattacks) are absorbed by the shield first until it is used up (whole battle); actively cast damage spells (onSpellHit) are absorbed too.
--- Works like Celestial Armor (h7CelestialArmor): a temporary reduction before the hit (h7SLLib.preHit), the original damage worked out backwards after the hit, charged to the shield, and the difference settled.
--- After each absorption this bonus is replaced by one with the remaining amount, so the stack's description shows it.
--- Parameters:
---   val   remaining absorption
---   icon  icon for display (needed when adding it again)

local TAG = "RuneShield"
local LINK = "H7_SHARE_LINK_H7C"
local STACK = "h7RuneShield"
local ANIM = "h7/fx/h7rShield"

function Script:own(unit)
	return unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" }):filter(function(b)
		return b:getStacking() == STACK
	end)
end

function Script:pool(unit)
	local list = self:own(unit)
	local best = 0
	for i = 1, list:size() do
		local v = list:getBonus(i):getVal()
		if v > best then best = v end
	end
	return best, list
end

function Script:setPool(server, battle, unit, left)
	local _, list = self:pool(unit)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
	if left > 0 then
		server:addUnitBonus(battle, unit, {
			type = "COMBAT_EVENT_TRIGGER",
			subtype = "heroes-memorial.h7:h7RuneShield",
			val = left,
			duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other,
			sourceID = "heroes-memorial.h7:h7RuneStoneFortune",
			stacking = STACK,
			icon = self.icon,
			addInfo = { icon = self.icon }
		}, false)
	end
end

local function log(server, battle, unit, absorbed)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_RUNE_LOG_H7C.description.5" },
		replaceStrings = { unit:getCreature():getNameTextID(math.max(1, unit:getCount())) },
		replaceNumbers = { absorbed }
	})
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if self:pool(unit) <= 0 then return end
	SL.preHit(server, battle, unit, TAG, LINK)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local dealt, full = SL.postHit(server, battle, unit, TAG, LINK, payload, self)
	if dealt == nil then return end
	local pool = self:pool(unit)
	if pool <= 0 or full <= 0 then
		SL.settle(server, battle, unit, dealt, full)
		return
	end
	local absorbed = math.min(full, pool)
	if unit:isAlive() then
		SL.anim(server, battle, { unit }, ANIM, "", 0.85)
	end
	SL.settle(server, battle, unit, dealt, full - absorbed)
	self:setPool(server, battle, unit, pool - absorbed)
	server:refreshBattleUnits(battle)
	log(server, battle, unit, absorbed)
end

function Script:onSpellHit(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local pool = self:pool(unit)
	if pool <= 0 then return end
	local entry = self:ownEntry(unit, payload)
	local before = entry and entry.unitBefore
	if before == nil then return end
	local lost = before:getAvailableHealth() - unit:getAvailableHealth()
	if lost <= 0 then return end
	local absorbed = math.min(lost, pool)
	SL.anim(server, battle, { unit }, ANIM, "", 0.85)
	server:healUnit(battle, unit, absorbed, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	self:setPool(server, battle, unit, pool - absorbed)
	server:refreshBattleUnits(battle)
	log(server, battle, unit, absorbed)
end

return Script
