local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Cloak (H4-H7 mechanic port, round 148; matches H7's Shadow Cloak)
---
--- At battle start it puts on a Shadow Cloak with val layers (default 2). Each attack it receives (melee, ranged or counterattack) uses up 1 layer and misses completely, no health lost;
--- until the layers run out, not restored this battle. Spell damage is not blocked. Clones have no cloak.
--- Done like Spirit Form: a hidden mark and 100% damage reduction before the hit; the engine deals at least 1 damage per hit, so after the hit the reduction is removed and the hit's damage restored.
--- Remaining layers shown on the stack (mark, value = remaining layers).
---
--- Parameters:
---   val   layers at battle start
---   mark  name of this mod's layer marker bonus (visible)
---   flag  name of this mod's hidden mark bonus (this hit missed); value description 1 is the battle log

local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local TAG = "h47Cloak"
local DODGE = TAG

--- Round 153: for the hit to miss completely, the reduction must offset negative reductions on the target (Nature's Revenge marks, Icebreaker etc. can make the reduction negative;
--- previously only 100% was added, so with a full -100% Nature's Revenge the whole hit still landed before being restored, and life drain, retribution etc. counted the full amount)
local function fullReduction(unit)
	local others = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= DODGE
	end):totalValue()
	return 100 + math.max(0, -others)
end

local ANIMATION = "h47/fx/fx_shadowCloak" -- Round 150: a dedicated shadow dodge animation (previously borrowed the Air Shield light C01SPA0)

local function own(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == TAG
	end)
end

function Script:charges(unit)
	local marks = unit:getBonuses({ type = self.mark })
	if marks:size() == 0 then return 0, marks end
	return marks:getBonus(1):getVal(), marks
end

function Script:setCharges(server, battle, unit, n)
	local _, marks = self:charges(unit)
	if marks:size() > 0 then server:removeUnitBonuses(battle, unit, marks) end
	if n <= 0 then return end
	server:addUnitBonus(battle, unit, {
		type        = self.mark,
		val         = n,
		duration    = ENUM.BonusDuration.oneBattle,
		sourceType  = ENUM.BonusSource.other,
		sourceID    = unit:getCreature():getJsonKey(),
	}, true)
end

function Script:clearDodge(server, battle, unit)
	local flags = unit:getBonuses({ type = self.flag })
	if flags:size() == 0 then return false end
	server:removeUnitBonuses(battle, unit, flags)
	local red = own(unit)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if red:size() > 0 then Proxy.removeExact(server, battle, unit, red) end
	return true
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isClone() then return end
	self:setCharges(server, battle, unit, self.val or 2)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	self:clearDodge(server, battle, unit)
	if not unit:isAlive() or unit:isClone() then return end
	if self:charges(unit) <= 0 then return end

	local source = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = self.flag, val = 1,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source, hidden = true
	}, true)
	server:addUnitBonus(battle, unit, {
		type = REDUCTION, subtype = ALL, val = fullReduction(unit), -- Round 153: previously fixed at 100
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		stacking = TAG, hidden = true
	}, true)
	-- Round 158: the engine deals at least 1 damage per hit. With only 1 health left, 1 is restored first so the "missed" hit does not kill the last creature
	if unit:getAvailableHealth() <= 1 then
		server:healUnit(battle, unit, 1, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not self:clearDodge(server, battle, unit) then return end
	-- Round 153: no healing if the stack is already dead (it used to revive it and still trigger Soul Hunter and Bloodsucker)
	if not unit:isAlive() then return end

	local entry = self:ownEntry(unit, payload)
	local damage = entry and entry.damage or 0
	if damage > 0 then
		server:healUnit(battle, unit, damage, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	end

	local left = self:charges(unit) - 1
	self:setCharges(server, battle, unit, left)

	server:showBattleAnimation(battle, { { unit = unit } }, ANIMATION, "", 0.5, true) server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus." .. self.flag .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { math.max(left, 0) }
	})
end

return Script
