local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local Proxy = require("lib/kadAiProxy") -- Round 354: the shared reduction is removed selectively, with removeExact
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Raise Shields (H6 Sentinel, Praetorian). Rewritten from the ported H4-H7 mechanic "Martyrdom" (h47MartyrGuard):
---
--- the shield bearer's ability (carrying mark, value = share %) is passed battle-wide (BATTLE_WIDE), so every stack carries this script:
---   while a friendly shield bearer is adjacent, mark% of the attack damage this stack takes (melee, ranged and counterattacks) is shared by the shield bearer (based on the actual damage of the hit).
---   The shield bearer blocks with its shield and only takes (100 - cut)% of its share. Spell damage is not shared.
---   Before the hit, the original target gets a temporary reduction (the shared part); after the hit that part is worked out from the actual damage and dealt to the shield bearer, then the reduction is removed.
---   With several adjacent shield bearers, the one with the most remaining health is chosen. Shield bearers do not share for themselves.
---   A single hit only goes through one kind of sharing (Martyrdom, Balance rune and Raise Shields share the stacking prefix h47Share); first come first served, no stacking.
---
--- Parameters:
---   mark  name of the shield marker bonus (on the shield bearer, shows the description; value = share)
---   link  name of the hidden mark bonus (on the original target; value description 1 is the battle log). Value = shield bearer id + 1 + (armor-type reduction measured before the hit + 1000) x 10000
---   cut   further percentage cut on the shield bearer's share, default 25

local SHARE = "h47Share"
local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local ANIMATION = "C01SPA0" -- Air Shield light effect

local function isShare(b)
	return string.sub(b:getStacking(), 1, #SHARE) == SHARE
end

local function shareReductions(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(isShare)
end

--- Total of the "armor-type" reductions in the damage calculation (spell sources and the shared part excluded)
local function otherReduction(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and not isShare(b)
	end):totalValue()
end

local function adjacent(a, b)
	local around = a:getSurroundingHexes()
	local hexes = b:getHexes()
	for i = 1, hexes:size() do
		if around:contains(hexes:at(i)) then return true end
	end
	return false
end

function Script:clear(server, battle, unit)
	local links = unit:getBonuses({ type = self.link })
	if links:size() == 0 then return nil end
	local v = links:getBonus(1):getVal()
	server:removeUnitBonuses(battle, unit, links)
	return v % 10000 - 1, math.floor(v / 10000) - 1000
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	-- Clear what was left from last time first
	if self:clear(server, battle, unit) ~= nil then
		local old = shareReductions(unit)
		if old:size() > 0 then Proxy.removeExact(server, battle, unit, old) end
	end

	if not unit:isAlive() then return end
	if shareReductions(unit):size() > 0 then return end -- This hit is already shared by something else

	local side = unit:getSide()
	local myId = unit:unitID()
	local martyrs = battle:getUnitsIf(function(u)
		return u:unitID() ~= myId and not battle:isHostile(u, unit) and u:isAlive() and not u:isGhost()
			and u:hasBonuses({ type = self.mark }) and adjacent(u, unit)
			and not u:isInvincible() -- Round 153: an invincible martyr does not take hits for others
	end)
	if #martyrs == 0 then return end

	local best = martyrs[1]
	for i = 2, #martyrs do
		if martyrs[i]:getAvailableHealth() > best:getAvailableHealth() then best = martyrs[i] end
	end

	local rest = otherReduction(unit)
	-- Round 153: the share is based on the damage the target would actually take (it used to be based on base damage, so with the target's own reduction the martyr got more than described,
	-- e.g. Shieldguard 15% reduction and 40% Martyrdom gave the martyr 47%). Added reduction = share x (100 - other reductions) / 100
	local share = math.min(best:getBonusesValue({ type = self.mark }), 75)
	local pct = math.min(math.floor(share * (100 - rest) / 100 + 0.5), 95 - rest)
	if pct <= 0 then return end

	local source = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = REDUCTION, subtype = ALL, val = pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		stacking = SHARE .. "H6Shieldguard", hidden = true
	}, true)
	server:addUnitBonus(battle, unit, {
		type = self.link, val = best:unitID() + 1 + (rest + 1000) * 10000,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		hidden = true
	}, true)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local id, rest = self:clear(server, battle, unit)
	if id == nil then return end

	local mine = shareReductions(unit)
	if mine:size() == 0 then return end
	local pct = mine:getBonus(1):getVal()
	Proxy.removeExact(server, battle, unit, mine)

	local entry = self:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	local denom = 100 - rest - pct
	if dealt <= 0 or denom <= 0 then return end

	local transfer = math.floor(dealt * pct / denom * (100 - (self.cut or 25)) / 100 + 0.5)
	if transfer <= 0 then return end

	local found = battle:getUnitsIf(function(u) return u:unitID() == id end)
	local martyr = found[1]
	if martyr == nil or not martyr:isAlive() or martyr:isInvincible() then return end

	server:showBattleAnimation(battle, { { unit = martyr } }, ANIMATION, "", 0.6, true)
	local done, killed = server:damageUnit(battle, martyr, transfer)
	server:appendLog(battle, {
		append         = { "core.bonus." .. self.link .. ".description.1" },
		replaceStrings = { martyr:getCreature():getNameTextID(martyr:getCount()), unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { done }
	})
	BattleLog.creaturesPerish(server, battle, martyr, killed)
end

return Script
