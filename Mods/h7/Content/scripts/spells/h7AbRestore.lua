local Base = require("spells/unitEffect")
local L = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Healing and resurrection active abilities of H7 creatures (on a friendly stack or friendly corpse, batch E):
---   mode = "resurrect"  Resurrect (Celestial): a living friendly stack (not undead, constructs or war machines) regains per x caster count health, can resurrect (permanently)
---   mode = "repair"     Master Welder (Cabir Master): a friendly construct regains per x caster count health, can resurrect (permanently).
---                       Construct = has MECHANICAL, GARGOYLE or NON_LIVING (this mod's "Construct" ability gives NON_LIVING) and is not undead or a war machine
--- Dead stacks can be chosen too (no living stack blocking the corpse's hex); clones and the caster itself cannot.
--- With the Ring of Oblivion (hota) in play it becomes normal healing: only the top creature is healed, no resurrection (as hota ringOfOblivionPatch.lua).
--- Uses are handled by spells/h7AbUse in the same spell.
--- Parameters: mode, per, animation, sound, log (battle log text id: "%s...%s...%d...%d")

local function isConstruct(u)
	if u:hasBonuses({ type = "UNDEAD" }) then return false end
	return u:hasBonuses({ type = "MECHANICAL" }) or u:hasBonuses({ type = "GARGOYLE" }) or u:hasBonuses({ type = "NON_LIVING" })
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or unit == nil then return false end
	if unit:unitID() == caster:unitID() then return false end
	if unit:getSide() ~= caster:getSide() then return false end
	if unit:isGhost() or unit:isClone() or unit:isTurret() then return false end
	if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end

	if self.mode == "repair" then
		if not isConstruct(unit) then return false end
	else
		if unit:hasBonuses({ type = "UNDEAD" }) or isConstruct(unit) then return false end
	end

	if unit:isDead() then
		local battle = mechanics:getBattle()
		local hexes = unit:getHexes()
		for i = 1, hexes:size() do
			local blocker = battle:getUnitByPos(hexes:at(i), true)
			if blocker ~= nil and blocker:unitID() ~= unit:unitID() then return false end
		end
		return true
	end
	return unit:isAlive() and unit:getAvailableHealth() < unit:getTotalHealth()
end

function Script:isReceptive(mechanics, unit)
	return true
end

--- getUnitsIf does not return corpses: use it for the living, and find corpses hex by hex with getUnitByPos(hex, false)
function Script:candidates(mechanics)
	local battle = mechanics:getBattle()
	local out = battle:getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end)
	if #out > 0 then return out end
	local seen = {}
	for _, h in pairs(L.hexTable(battle)) do
		local u = battle:getUnitByPos(h, false)
		if u ~= nil and not seen[u:unitID()] then
			seen[u:unitID()] = true
			if u:isDead() and self:isValidTarget(mechanics, u) then out[#out + 1] = u end
		end
	end
	return out
end

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil or #self:candidates(mechanics) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

--- Corpses and wounded targets do not go through the engine's "accepts spell" filter
function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local d = (spellTarget and spellTarget[1]) or (aimPoint and aimPoint[1])
	if d == nil then return {} end
	if d.unit ~= nil then return { { unit = d.unit, hex = d.unit:getPosition() } } end
	if d.hex ~= nil and d.hex:isValid() then
		local battle = mechanics:getBattle()
		local u = battle:getUnitByPos(d.hex, true) or battle:getUnitByPos(d.hex, false)
		if u ~= nil then return { { unit = u, hex = u:getPosition() } } end
	end
	return {}
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil or not self:isValidTarget(mechanics, unit) then return end

	local amount, level = L.reviveHeal(unit, (self.per or 0) * caster:getCount())
	local healed, raised = 0, 0
	if amount > 0 then
		healed, raised = server:healUnit(battle, unit, amount, level, ENUM.HealPower.permanent)
	end

	if server:describeChanges() then
		if self.animation then
			server:showBattleAnimation(battle, { { unit = unit } }, self.animation, self.sound or "", 1.0, true)
		end
		server:refreshBattleUnits(battle)
		if self.log then L.log(server, battle, self.log, { L.name(caster), L.name(unit) }, { healed or 0, raised or 0 }) end
	end
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Resurrection (Celestial), Master Welder: heal and resurrect allies
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

--- Hover estimate: same formula as apply. per x number of casters healing (can resurrect, permanent; with the Ring of Oblivion on the field only the top creature is healed, no resurrection),
--- shows the health actually restored and the number resurrected
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil then return zero end
		local dest = self:filterTarget(mechanics, spellTarget or {})[1]
		local unit = dest and dest.unit
		if unit == nil then return zero end
		local amount, level = L.reviveHeal(unit, (self.per or 0) * caster:getCount())
		if amount <= 0 then return zero end
		local healed, raised = unit:copy():heal(math.floor(amount), level, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = unit:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
