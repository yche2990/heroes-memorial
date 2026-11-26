local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Wail of the Netherworld (H6 Spectre)
---
--- On a friendly undead stack (can be itself): every living enemy adjacent to it loses per x number of Spectres health,
--- and the target regains per x number of Spectres plus all the drained health (can resurrect, permanent).
--- Parameters: per, uses, key, animation (heal), drainAnimation (drained), sound, drainSound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not unit:isAlive() or unit:isGhost() or unit:isTurret() then return false end
	if mechanics:getBattle():isHostile(caster, unit) then return false end
	return L.isUndead(unit)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local found = mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end)
	if #found == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local unit = target[1] and target[1].unit
	if unit == nil or not unit:isAlive() then return end
	local amount = (self.per or 6) * caster:getCount()
	local drained, n = 0, 0
	local victims = L.around(battle, unit, function(u) return battle:isHostile(caster, u) and L.isLiving(u) and not u:isInvincible() end)
	for _, v in ipairs(victims) do
		local d = L.hit(server, battle, v, math.min(amount, v:getAvailableHealth()), self.drainAnimation, self.drainSound)
		drained = drained + (d or 0); n = n + 1
	end
	if self.animation and server:describeChanges() then
		server:showBattleAnimation(battle, { { unit = unit } }, self.animation, self.sound or "", 1.0, true)
	end
	local amt, lvl = L.reviveHeal(unit, amount + drained)   -- Ring of Oblivion
	local healed, raised = server:healUnit(battle, unit, amt, lvl, ENUM.HealPower.permanent)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_WAIL_H6C", 1, { L.name(caster), L.name(unit) }, { n, drained, healed or 0, raised or 0 })
	L.useCast(server, battle, caster, self.key or "h6Wail", self.uses)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Wail of the Underworld: cast on a friendly undead stack, which heals and resurrects (draining nearby enemies)
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

--- Hover estimate: same formula as apply. The target (friendly undead) heals per x number of wraiths, plus the health drained from adjacent living enemy stacks
--- (at most per x number of wraiths from each, not more than its remaining health); can resurrect, with the Ring of Oblivion on the field only the top creature is healed. Shows the health actually restored and the number resurrected
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil then return zero end
		local dest = self:filterTarget(mechanics, spellTarget or {})[1]
		local unit = dest and dest.unit
		if unit == nil or not unit:isAlive() then return zero end
		local battle = mechanics:getBattle()
		local amount = (self.per or 6) * caster:getCount()
		local drained = 0
		local victims = L.around(battle, unit, function(u) return battle:isHostile(caster, u) and L.isLiving(u) and not u:isInvincible() end)
		for _, v in ipairs(victims) do
			drained = drained + math.min(amount, v:getAvailableHealth())
		end
		local amt, lvl = L.reviveHeal(unit, amount + drained)
		local healed, raised = unit:copy():heal(math.floor(amt), lvl, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = unit:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
