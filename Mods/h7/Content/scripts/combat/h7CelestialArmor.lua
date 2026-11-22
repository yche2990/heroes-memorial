local Base = require("combat/combatScript")
local L = require("heroes-memorial.h7:combat/h7SLLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Celestial Armor (H7): added by the spell h7CelestialArmor (heroes-memorial:h5Attach); val = total damage it can still absorb.
--- Attacks taken (melee, ranged, counterattacks) are absorbed by the armor first until it is used up; it disappears when used up or after 3 rounds.
--- How it works: a temporary reduction before the hit (h7SLLib.preHit); after the hit the original damage is worked out backwards and charged to the armor, dealing what was over-absorbed and healing what was under-absorbed.
--- Spell damage (actively cast, onSpellHit) is absorbed too: after the hit the lost health is restored, up to the remaining total.
--- After each absorption this combat event bonus is replaced by one with the remaining amount (same source, stacking and remaining rounds), so the stack's description shows the remaining amount.
---
--- Parameters:
---   val   remaining absorption (at cast time = base + per point of Spell Power x Spell Power)
---   icon  icon for display (needed when adding it again)

local TAG = "Celestial"
local LINK = "H7_SHARE_LINK_H7C"
local KEY = "h7CelestialArmor"
local ANIM = "h7/fx/slCelestialArmorTick"
local SOUND = "h7/spell_celestial_armor_tick.ogg"

function Script:own(unit)
	return L.ownBonuses(unit, "COMBAT_EVENT_TRIGGER", KEY):filter(function(b)
		return string.find(tostring(b:getSubtype() or ""), KEY, 1, true) ~= nil
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

--- Write the remaining amount back: remove the armor if <= 0
function Script:setPool(server, battle, unit, left)
	local _, list = self:pool(unit)
	if list:size() == 0 then return end
	local b = list:getBonus(1)
	local turns = b:getTurnsRemain()
	local d = {
		type = "COMBAT_EVENT_TRIGGER",
		subtype = b:getSubtype(),
		val = left,
		duration = ENUM.BonusDuration.nTurns,
		turns = turns,
		sourceType = ENUM.BonusSource.spellEffect,
		sourceID = b:getSourceID(),
		sourceSecondaryID = self.attachLevel or 0, -- H7 audit A1: write the casting level back when adding it again (h5Attach puts it in addInfo.attachLevel)
		stacking = b:getStacking(),
		addInfo = { icon = self.icon, attachLevel = self.attachLevel }
	}
	if self.icon then d.icon = self.icon end
	server:removeUnitBonuses(battle, unit, list)
	if left > 0 and turns > 0 then
		server:addUnitBonus(battle, unit, d, false)
	end
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if self:pool(unit) <= 0 then return end
	L.preHit(server, battle, unit, TAG, LINK)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local dealt, full = L.postHit(server, battle, unit, TAG, LINK, payload, self)
	if dealt == nil then return end
	local pool = self:pool(unit)
	if pool <= 0 or full <= 0 then
		L.settle(server, battle, unit, dealt, full)
		return
	end
	local absorbed = math.min(full, pool)
	if unit:isAlive() then
		L.anim(server, battle, { unit }, ANIM, SOUND, 0.85)
	end
	L.settle(server, battle, unit, dealt, full - absorbed)
	self:setPool(server, battle, unit, pool - absorbed)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { absorbed }
	})
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
	L.anim(server, battle, { unit }, ANIM, SOUND, 0.85)
	server:healUnit(battle, unit, absorbed, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	self:setPool(server, battle, unit, pool - absorbed)
	server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus.H7_SL_LOG_H7C.description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { absorbed }
	})
end

return Script
