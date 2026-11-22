local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local L = require("combat/h7dLib")
local Z = require("combat/h7dZones")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Damage sharing of the H7 Rune of Balance (battle-wide hidden script, added with addBattleBonus by h7RuneOfBalance at battle start; every stack inherits a copy).
---
--- When a stack stands in its side's Balance rune aura (the rune hex or the hexes occupied by a Rune Priest with the aura and the ring around them; one hex inside is enough) and there are k other
--- real friendly stacks in the aura (arrow towers, war machines and invincible stacks excluded), damage it takes from attacks (melee, ranged and counterattacks; not spell damage) is split among k+1 stacks:
--- before the hit it gets a temporary reduction of k/(k+1) (scaled after its existing all-damage reduction, at most 95%); after the hit the shared part is worked out from the actual damage
--- and split among the other allies in the aura (health subtracted directly, without Defense again). Done like h47BalanceRune of tears-of-ashan (rounds 145, 153).
--- Parameters: none

local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local MINE = "h7RuneShare"
local LINK = "H7_RUNE_LINK_H7C"

local function mine(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == MINE
	end)
end

--- Temporary reductions added by other sharing / absorbing effects ("h7Share..." of h7SLLib: Celestial Armor, Martyrdom, Shield of Fate; "h47Share..." of tears-of-ashan)
local function isOtherShare(b)
	local s = b:getStacking()
	return string.sub(s, 1, 7) == "h7Share" or string.sub(s, 1, 8) == "h47Share"
end

local function otherReduction(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= MINE and not isOtherShare(b)
	end):totalValue()
end

--- H7 audit A2: this script's priority is -10 (scripts.json), so it settles before Celestial Armor and the like both before and after the hit, and this is normally 0 here;
--- if another sharing reduction is already present, the total stays at most 95%
local function otherShares(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(isOtherShare):totalValue()
end

local function partners(battle, unit)
	local side = unit:getSide()
	local area = Z.runeArea(battle, side)
	if area == nil or not Z.inArea(unit, area) then return {} end
	local id = unit:unitID()
	return battle:getUnitsIf(function(u)
		return u:unitID() ~= id and u:getSide() == side and L.isReal(u) and not u:isInvincible() and Z.inArea(u, area)
	end)
end

local function clearLink(server, battle, unit)
	local links = unit:getBonuses({ type = LINK })
	if links:size() == 0 then return false, 0 end
	local rest = links:getBonus(1):getVal() - 1000
	server:removeUnitBonuses(battle, unit, links)
	return true, rest
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if clearLink(server, battle, unit) then
		local old = mine(unit)
		if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	end
	if not L.isReal(unit) then return end
	local k = #partners(battle, unit)
	if k == 0 then return end
	local rest = otherReduction(unit)
	local share = math.floor(100 * k / (k + 1))
	local pct = math.min(math.floor(share * (100 - rest) / 100 + 0.5), 95 - rest - otherShares(unit))
	if pct <= 0 then return end
	local source = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = REDUCTION, subtype = ALL, val = pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		stacking = MINE, hidden = true
	}, true)
	server:addUnitBonus(battle, unit, {
		type = LINK, val = rest + 1000,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local linked, rest = clearLink(server, battle, unit)
	if not linked then return end
	local m = mine(unit)
	if m:size() == 0 then return end
	local pct = m:getBonus(1):getVal()
	Proxy.removeExact(server, battle, unit, m)

	local entry = self:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	local denom = 100 - rest - pct
	if dealt <= 0 or denom <= 0 then return end
	local transfer = math.floor(dealt * pct / denom + 0.5)
	local list = partners(battle, unit)
	local k = #list
	if transfer <= 0 or k == 0 then return end

	local each = math.floor(transfer / k)
	local extra = transfer - each * k
	local total = 0
	for i, p in ipairs(list) do
		local amount = each + ((i <= extra) and 1 or 0)
		if amount > 0 then
			server:showBattleAnimation(battle, { { unit = p } }, "h7/fx/h7dRuneCast", "", 0.6, true)
			local done, killed = server:damageUnit(battle, p, amount)
			total = total + (done or 0)
			BattleLog.creaturesPerish(server, battle, p, killed)
		end
	end
	L.log(server, battle, 3, { L.name(unit) }, { total, k })
end

return Script
