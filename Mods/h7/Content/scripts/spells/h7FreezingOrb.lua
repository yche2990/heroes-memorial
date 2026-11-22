--- Freezing Orb (H7): summons a single-hex Freezing Orb on the chosen free hex (temporary summon, gone after battle).
--- The orb cannot act or counterattack and counts as a war machine (does not affect victory), health = hp[mastery] (400/700/1100/1600).
--- When it lands and at the end of each later round (before the next round starts) it releases a 3x3 frost aura: adjacent enemies take Water damage
--- and are slowed by 3 (3 rounds); at the end of each round it first moves, ignoring obstacles, to the free hex "farthest from it and right next to an enemy" before releasing it.
--- The orb lasts until the end of the 2nd round after (or until destroyed).
--- Damage = base[mastery] + perPower[mastery] x Spell Power (fixed at cast time; the average of H7's minimum and maximum damage).
--- Parameters: creature (orb creature, id within this mod), tickScript (the combat event script on the orb, full id),
---       hp, base, perPower (4 numbers), rounds (how many more moves after landing, default 2)
local Base = require("spells/spellEffect")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Orb = require("heroes-memorial.h7:combat/h7FreezingOrbTick")
local Proxy = require("lib/kadAiProxy")   -- Round 401: AI simulation branch
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:describeTargetStep()
	return nil
end

function Script:orbCreature()
	return Lib.creature(self.creature or "h7FreezingOrbUnit")
end

function Script:applicableGeneral(mechanics, problem)
	if self:orbCreature() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local source = spellTarget
	if #source == 0 then source = aimPoint end
	for _, dest in ipairs(source) do
		if dest.hex ~= nil and dest.hex:isValid() then return { { hex = dest.hex } } end
	end
	return {}
end

function Script:hexAllowed(mechanics, hex)
	local c = self:orbCreature()
	if c == nil or hex == nil or not hex:isValid() then return false end
	return mechanics:getBattle():isAccessibleForNewUnit(hex, c, mechanics:getCasterSide())
end

function Script:applicableTarget(mechanics, problem, target)
	if #target == 0 or not self:hexAllowed(mechanics, target[1].hex) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	for _, dest in ipairs(spellTarget) do
		if dest.hex ~= nil and dest.hex:isValid() then hexes:insert(dest.hex) end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	if #target == 0 then return end
	local creature = self:orbCreature()
	local hex = target[1].hex
	if creature == nil or not self:hexAllowed(mechanics, hex) then return end

	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local hp = math.max(1, math.floor(Lib.pick(self.hp, lvl)))
	local dmg = math.max(1, math.floor(Lib.pick(self.base, lvl) + Lib.pick(self.perPower, lvl) * sp))

	-- Round 401: AI simulation branch. An orb summoned on the imaginary battlefield has no valid side, and releasing the aura would fail;
	-- so the landing aura is reported instead: enemies adjacent to the landing hex take dmg Water damage each (later auras and slowing not counted; a conservative estimate)
	if Proxy.trial(server) then
		local side = mechanics:getCasterSide()
		for _, u in ipairs(battle:getUnitsIf(function(x)
			return x:isAlive() and not x:isGhost() and not x:isTurret() and x:getSide() ~= side and Proxy.unitDistance(x, hex) == 1
		end)) do
			Proxy.damage(server, battle, u, dmg, { school = "water" })
		end
		return
	end

	local orb = server:addUnit(battle, {
		count    = 1,
		type     = creature,
		side     = mechanics:getCasterSide(),
		position = hex,
		summoned = true
	})
	if orb == nil then return end

	-- The creature's health is written as the highest, 1600; lower masteries subtract the excess from this one
	local excess = creature:getMaxHealth() - hp
	if excess > 0 then
		local state = orb:copy()
		state:damage(excess)
		server:changeUnit(battle, state, 0)
	end

	server:addUnitBonus(battle, orb, {
		type       = "COMBAT_EVENT_TRIGGER",
		subtype    = self.tickScript or "heroes-memorial.h7:h7FreezingOrbTick",
		val        = dmg,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.creatureAbility,   -- Not a spell effect: Dispel cannot remove the orb's aura
		sourceID   = creature:getJsonKey(),
		hidden     = true
	}, true)
	Orb.setLeft(server, battle, orb, self.rounds or 2)
	server:refreshBattleUnits(battle)

	-- First aura on landing
	Orb.pulse(server, battle, orb, dmg)
end

return Script
