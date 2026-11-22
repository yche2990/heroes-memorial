local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local BattleLog = require("battleLog")
local L = require("combat/h5B3Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Bloodthirsty: Taunt
---
--- The Bloodthirsty (mark H5_TAUNT_H5C) passes this script to all allies (BATTLE_WIDE + own side only, one per stacking group).
--- When an enemy attacks (melee or ranged, not retaliation) an ally adjacent to the Bloodthirsty, the Bloodthirsty has a chance (ProcFactor = pf, by the ratio of the Bloodthirsty's and the attacker's
--- total health) to draw the hit onto itself. Done like Martyrdom (h47MartyrGuard): before the hit the original target gets a temporary damage reduction,
--- after the hit the blocked part is worked out from the actual damage and dealt to the Bloodthirsty. The engine requires at least 1 damage per hit and caps reduction at 95%,
--- so the original target still takes about 5%. With several adjacent Bloodthirsty, the one with the most remaining health is chosen; a Bloodthirsty does not cover for itself.
--- Shares the stacking prefix h47Share with Martyrdom and the Rune of Balance; only one kind of sharing applies per hit.
---
--- Parameter: pf

local SHARE = "h47Share"
local STACK = SHARE .. "Taunt"
local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local LINK = "H5_TAUNT_LINK_H5C"

local function isShare(b)
	return string.sub(b:getStacking(), 1, #SHARE) == SHARE
end

local function shareReductions(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(isShare)
end

local function otherReduction(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and not isShare(b)
	end):totalValue()
end

function Script:clear(server, battle, unit)
	local links = unit:getBonuses({ type = LINK })
	if links:size() == 0 then return nil end
	local v = links:getBonus(1):getVal()
	server:removeUnitBonuses(battle, unit, links)
	return v % 10000 - 1, math.floor(v / 10000) - 1000
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if self:clear(server, battle, unit) ~= nil then
		local old = shareReductions(unit):filter(function(b) return b:getStacking() == STACK end)
		-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
		if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	end
	if not unit:isAlive() or other == nil or payload.isCounter then return end
	if not battle:isHostile(other, unit) then return end
	if shareReductions(unit):size() > 0 then return end

	local side, myId = unit:getSide(), unit:unitID()
	local taunters = battle:getUnitsIf(function(u)
		return u:unitID() ~= myId and not battle:isHostile(u, unit) and u:isAlive() and not u:isGhost()
			and not u:isInvincible() and u:hasBonuses({ type = "H5_TAUNT_H5C" }) and L.adjacent(u, unit)
	end)
	if #taunters == 0 then return end
	local best = taunters[1]
	for i = 2, #taunters do
		if taunters[i]:getAvailableHealth() > best:getAvailableHealth() then best = taunters[i] end
	end
	if not server:rollCombatAbility(battle, best, L.procChance(best, other, self.pf or 1.2)) then return end

	local rest = otherReduction(unit)
	local pct = 95 - rest
	if pct <= 0 then return end
	local src = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = REDUCTION, subtype = ALL, val = pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = STACK, hidden = true
	}, true)
	server:addUnitBonus(battle, unit, {
		type = LINK, val = best:unitID() + 1 + (rest + 1000) * 10000,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = src, hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local id, rest = self:clear(server, battle, unit)
	if id == nil then return end
	local mine = shareReductions(unit):filter(function(b) return b:getStacking() == STACK end)
	if mine:size() == 0 then return end
	local pct = mine:getBonus(1):getVal()
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	Proxy.removeExact(server, battle, unit, mine)

	local entry = self:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	local denom = 100 - rest - pct
	if dealt <= 0 or denom <= 0 then return end
	local transfer = math.floor(dealt * pct / denom + 0.5)
	if transfer <= 0 then return end

	local found = battle:getUnitsIf(function(u) return u:unitID() == id end)
	local taunter = found[1]
	if taunter == nil or not taunter:isAlive() or taunter:isInvincible() then return end
	local done, killed = server:damageUnit(battle, taunter, transfer)
	server:appendLog(battle, {
		append = { "core.bonus.H5_TAUNT_H5C.description.900001" },
		replaceStrings = { taunter:getCreature():getNameTextID(taunter:getCount()), unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { done }
	})
	BattleLog.creaturesPerish(server, battle, taunter, killed)
end

return Script
