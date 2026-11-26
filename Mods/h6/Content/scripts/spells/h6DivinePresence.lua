local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Divine Presence (H6 Uriel): a friendly stack (alive or dead) is restored to full battle-start health (can resurrect, permanent), all negative spells are dispelled,
--- and it is immune to negative spells for the rest of the battle (cannot be dispelled). Parameters: key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit == nil or unit:isGhost() or mechanics:getBattle():isHostile(caster, unit) then return false end
	if unit:isTurret() or unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return unit:getAvailableHealth() < L.initialHealth(unit) or not unit:hasBonuses({ type = "H6_DIVINE_H6C" })
end
function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget); return false
end
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or main == nil then return end
	local amt, lvl = L.reviveHeal(main, L.initialHealth(main))   -- Ring of Oblivion
	server:healUnit(battle, main, amt, lvl, ENUM.HealPower.permanent)
	local neg = main:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		local sp = LIBRARY:getSpellByName(b:getSourceID())
		return sp ~= nil and sp:isNegative()
	end)
	if neg:size() > 0 then server:removeUnitBonuses(battle, main, neg) end
	if not main:hasBonuses({ type = "H6_DIVINE_H6C" }) then
		local src = caster:getCreature():getJsonKey()
		server:addUnitBonus(battle, main, { type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "spellSchool.any", val = 0, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Divine" }, true)
		server:addUnitBonus(battle, main, { type = "H6_DIVINE_H6C", val = 1, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6Divine" }, true)
	end
	L.show(server, battle, { main }, self.animation, self.sound)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Divine Presence: allies heal to their health at the start of battle (can resurrect)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "combatHeal" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

--- Hover estimate: same formula as apply. Heals back to the health at the start of battle (can resurrect, permanent; with the Ring of Oblivion on the field only the top creature is healed). Shows the health restored and the number resurrected
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if mechanics:getUnitCaster() == nil or main == nil then return zero end
		local amt, lvl = L.reviveHeal(main, L.initialHealth(main))
		amt = math.floor(amt)
		if amt <= 0 then return zero end
		local healed, raised = main:copy():heal(amt, lvl, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = main:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
