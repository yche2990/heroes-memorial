local Base = require("spells/spellEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Fire Sentry (H7): summons a one-hex Fire Sentry on the chosen free hex (creature, summoned, cannot act, does not retaliate,
--- health = hp[mastery]: each creature has 1 health, so the count is the remaining health).
--- The sentry carries hidden marks: H7_FIRESENTRY_H7C = damage per shot (base + perPower x Magic, H7 average),
--- H7_FIRESENTRY_LIFE_H7C = how many end-of-round shots remain (shots, default 3: H7 "lasts until the end of the 2nd round after").
--- Shooting is done by the battle-wide combat event watchScript (h7FireSentry): at the end of the round (start of the next in VCMI) it hits the two nearest enemies,
--- and every round shoots back at the shooter after the enemy's first ranged attack.
--- Parameters: creature, hp, base, perPower (4 numbers each), shots, watchScript

function Script:applicableTarget(mechanics, problem, target)
	local dest = target[1]
	if dest == nil or dest.hex == nil or not dest.hex:isValid() or not dest.hex:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	local battle = mechanics:getBattle()
	local creature = LIBRARY:getCreatureByName(self.creature)
	if creature == nil or battle:getUnitByPos(dest.hex, true) ~= nil
		or not battle:isAccessibleForNewUnit(dest.hex, creature, mechanics:getCasterSide()) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	for _, dest in ipairs(spellTarget) do
		if dest.hex and dest.hex:isValid() then hexes:insert(dest.hex) end
	end
	return hexes
end

local function mark(server, battle, unit, typeName, val, spellKey, level)
	server:addUnitBonus(battle, unit, {
		type       = typeName,
		val        = val,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.spellEffect,
		sourceID   = spellKey,
		sourceSecondaryID = level, -- H7 audit A1: the casting level is stated, otherwise the description is taken for "any level" and goes out of range when right-clicking the stack
		stacking   = typeName,
		hidden     = true
	}, false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local dest = target[1]
	if dest == nil or dest.hex == nil then return end
	local creature = LIBRARY:getCreatureByName(self.creature)
	if creature == nil then return end
	local lvl, sp = Lib.level(mechanics), Lib.power(mechanics)
	local hp = math.floor(Lib.value(self.hp, nil, lvl, sp))
	local dmg = math.floor(Lib.value(self.base, self.perPower, lvl, sp))
	if hp <= 0 then return end
	local spellKey = mechanics:getSpell():getJsonKey()
	local unit = server:addUnit(battle, {
		count = hp,
		type = creature,
		side = mechanics:getCasterSide(),
		position = dest.hex,
		summoned = true
	})
	if unit == nil then return end
	mark(server, battle, unit, "H7_FIRESENTRY_H7C", math.max(1, dmg), spellKey, mechanics:getEffectLevel())
	mark(server, battle, unit, "H7_FIRESENTRY_LIFE_H7C", self.shots or 3, spellKey, mechanics:getEffectLevel())
	if server:describeChanges() then
		-- Battle-wide combat event: every stack carries it and the script decides itself who is a sentry and who is a shooter; one per stacking group
		server:addBattleBonus(battle, {
			type       = "COMBAT_EVENT_TRIGGER",
			subtype    = self.watchScript or "h7FireSentry",
			val        = 1,
			duration   = ENUM.BonusDuration.oneBattle,
			-- H7 audit A1: the source of the battle-wide carrier is now OTHER (it used to be a spell effect, so every stack's spell list showed an extra "Fire Sentry")
			sourceType = ENUM.BonusSource.other,
			stacking   = "h7FireSentryWatch",
			hidden     = true
		})
	end
	server:refreshBattleUnits(battle)
end

--- Round 301: newer engines call this every time a target is chosen; returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: cursor kadCursorSummon; summons a Fire Sentry on a free hex.
--- Hexes where it fits show "Cast X" (as the engine default, with the estimate); hexes where it does not fit show the original "X cannot be placed here" (core.genrltxt.181),
--- where the engine default would show no text at all.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	if #partialTarget ~= 0 or hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local spellName = mechanics:getSpell():getNameTextID()
	return {
		cursor = "kadCursorSummon",
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
		blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } }, -- %s cannot be placed here
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
