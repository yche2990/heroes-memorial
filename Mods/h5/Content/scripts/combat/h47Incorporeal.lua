local Base = require("combat/combatScript")
local Proxy = require("lib/kadAiProxy")   -- Round 344: precise bonus removal (mark-fix)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Incorporeal (H4-H7 mechanics port, round 128; matches the H6 Ghost; animation added in round 129)
---
--- Every time it is attacked (melee, ranged, retaliation) it has a val% chance to turn into a phantom: this hit deals almost no damage. Spell damage as usual.
--- How: roll before the hit; on success it gets a hidden mark and 100% damage reduction; the engine requires at least 1 damage per hit,
--- so after the hit the reduction is removed and the damage of this hit is restored.
---
--- Parameters:
---   val   trigger chance (%). With Deduction (changechanceskill) the hero raises it by 20%/50%/100% by skill level (round 152)
---   mark  hidden mark bonus name of this mod (each mod uses a different name, e.g. "H47_GHOST_NEVERMORE")
---         Mark value description 1 is the battle log text

local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL       = "damageTypeAll"
local DODGE     = "h47GhostDodge" -- Round 153: reductions attached by this script are identified by this stacking group

--- Round 153: for the hit to miss completely, the reduction must offset negative reductions on the target (Nature's Revenge marks, Icebreaker etc. can make the reduction negative;
--- previously only 100% was added, so with a full -100% Nature's Revenge the whole hit still landed before being restored, and life drain, retribution etc. counted the full amount)
local function fullReduction(unit)
	local others = unit:getBonuses({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll" }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and b:getStacking() ~= DODGE
	end):totalValue()
	return 100 + math.max(0, -others)
end


--- Reductions attached by this script (stacking group DODGE), told apart from the creature's own reductions
local function ownReductions(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == DODGE
	end)
end

--- Removes the mark and reduction; returns whether this hit was turned into a phantom
function Script:clearDodge(server, battle, unit)
	local marks = unit:getBonuses({ type = self.mark })
	if marks:size() == 0 then return false end

	server:removeUnitBonuses(battle, unit, marks)

	local reductions = ownReductions(unit)
	-- Round 344: precise removal (the engine ignores the stacking group when removing and would also remove other bonuses of the same type, source and value)
	if reductions:size() > 0 then Proxy.removeExact(server, battle, unit, reductions) end

	return true
end

--- Deduction (changechanceskill, round 152): the hero's Deduction raises the chance of probability-based creature abilities by 20%/50%/100%,
--- through a hidden bonus CHANGECHANCE_BOOST (value = percent increase). Without the Deduction mod this type is not found and counts as 0.
local function chanceBoost(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "CHANGECHANCE_BOOST" }) end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 0
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	-- Clear what was left last time (e.g. an attack interrupted halfway)
	self:clearDodge(server, battle, unit)

	if not unit:isAlive() then return end

	local chance = self.val or 0
	if chance <= 0 then return end
	chance = math.floor(chance * (100 + chanceBoost(unit)) / 100) -- Round 152: Deduction
	if chance < 100 and server:rngInt(1, 100) > chance then return end

	local source = unit:getCreature():getJsonKey()

	server:addUnitBonus(battle, unit, {
		type       = self.mark,
		val        = 1,
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = source,
		hidden     = true
	}, true)

	server:addUnitBonus(battle, unit, {
		type       = REDUCTION,
		subtype    = ALL,
		val        = fullReduction(unit),
		duration   = ENUM.BonusDuration.nTurns,
		turns      = 1,
		sourceType = ENUM.BonusSource.other,
		sourceID   = source,
		stacking   = DODGE,
		hidden     = true
	}, true)
	-- Round 158: the engine deals at least 1 damage per hit. With only 1 health left, 1 is restored first so the "missed" hit does not kill the last creature
	if unit:getAvailableHealth() <= 1 then
		server:healUnit(battle, unit, 1, ENUM.HealLevel.heal, ENUM.HealPower.permanent)
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not self:clearDodge(server, battle, unit) then return end
	if not unit:isAlive() then return end

	local entry = self:ownEntry(unit, payload)
	local damage = entry and entry.damage or 0

	if damage > 0 then
		server:healUnit(battle, unit, damage, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
	end

	-- Turning into a phantom: the translucent glow of Air Shield
	server:showBattleAnimation(battle, { { unit = unit } }, "h47/fx/fx_ghostDodge", "", 0.8, true) server:refreshBattleUnits(battle) -- Round 150: dedicated phantom animation (it used to borrow the Air Shield glow C01SPA0)

	server:appendLog(battle, {
		append         = { "core.bonus." .. self.mark .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(2) }
	})
end

return Script
