local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Healing and resurrection active abilities of H6 Haven (on a stack or a corpse):
---   Ally (alive and wounded, or dead with an unoccupied corpse): regains per x number of casters health, can resurrect (permanent)
---   Evil enemy stacks (Necropolis, Inferno, Dungeon and Stronghold creatures): take dmg x number of casters Light damage (scaled by Light and all-spell reduction)
--- Parameters:
---   per    health restored per caster
---   dmg    damage dealt to evil stacks per caster (0 = cannot target enemies)
---   uses   uses per battle (unlimited if omitted)
---   boost  if true (Blade of Revelation), the saved ally gets Morale +3 and Speed +2 for 2 rounds
---   key    counting mark
---   animation / sound  hit animation and sound

local EVIL = { necropolis = true, inferno = true, dungeon = true, stronghold = true }

local function isEvil(u)
	if u:hasBonuses({ type = "UNDEAD" }) then return true end
	local ok, f = pcall(function() return u:getCreature():getFaction():getJsonKey() end)
	if ok and f then
		local short = f:match(":(.+)$") or f
		return EVIL[short] == true
	end
	return false
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	if unit:isGhost() or unit:isClone() or unit:isTurret() then return false end
	if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	local battle = mechanics:getBattle()
	if battle:isHostile(caster, unit) then
		return (self.dmg or 0) > 0 and unit:isAlive() and not unit:isInvincible() and isEvil(unit)
	end
	if unit:isDead() then
		local hexes = unit:getHexes()
		for i = 1, hexes:size() do
			local blockers = battle:getUnitsIf(function(o) return o:isValidTarget(false) and o:coversPos(hexes:at(i)) end)
			if #blockers > 0 then return false end
		end
		return true
	end
	return unit:isAlive() and unit:getAvailableHealth() < unit:getTotalHealth()
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

local function lightReduction(u)
	local r = u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any" })
	local ok, l = pcall(function() return u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.01lightSchool" }) end)
	if ok and l then r = r + l end
	return math.min(r, 100)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil then return end
	local n = caster:getCount()

	if battle:isHostile(caster, unit) then
		local amount = math.floor((self.dmg or 0) * n * (100 - lightReduction(unit)) / 100)
		if amount > 0 then
			local dealt = L.hit(server, battle, unit, amount, self.animation, self.sound)
			L.log(server, battle, "H6_RESTORE_H6C", 2, { L.name(caster), L.name(unit) }, { dealt })
		end
	else
		local lvl = ENUM.HealLevel.resurrect
		local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
		if ok and ring then lvl = ENUM.HealLevel.heal end
		if self.animation and server:describeChanges() then
			server:showBattleAnimation(battle, { { unit = unit } }, self.animation, self.sound or "", 1.0, true)
		end
		local healed, raised = server:healUnit(battle, unit, (self.per or 0) * n, lvl, ENUM.HealPower.permanent)
		if self.boost and unit:isAlive() then
			L.removeByStacking(server, battle, unit, "MORALE", "h6Epiphany")
			L.removeByStacking(server, battle, unit, "STACKS_SPEED", "h6Epiphany")
			L.addBonus(server, battle, unit, { type = "MORALE", val = 3, duration = ENUM.BonusDuration.nTurns, turns = 2, stacking = "h6Epiphany" }, false)
			L.addBonus(server, battle, unit, { type = "STACKS_SPEED", val = 2, duration = ENUM.BonusDuration.nTurns, turns = 2, stacking = "h6Epiphany" }, false)
		end
		if server:describeChanges() then server:refreshBattleUnits(battle) end
		L.log(server, battle, "H6_RESTORE_H6C", 1, { L.name(caster), L.name(unit) }, { healed or 0, raised or 0 })
	end
	L.useCast(server, battle, caster, self.key or "h6Restore", self.uses)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Blade of Enlightenment, Blade of Mercy, Heal: heal and resurrect allies
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
		-- When pointing at an enemy stack (damage or no effect) use the engine default
		if unit ~= nil and unit:getSide() ~= mechanics:getCasterSide() then return nil end
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

--- Hover estimate: same formula as apply. Evil enemy stacks: dmg x number of casters, damage and kills after light and all-spell reductions;
--- allies: per x number of casters healing (can resurrect; with the Ring of Oblivion on the field only the top creature is healed), using the health actually restored and the number resurrected
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil then return zero end
		local dest = self:filterTarget(mechanics, spellTarget or {})[1]
		local unit = dest and dest.unit
		if unit == nil then return zero end
		local n = caster:getCount()
		local copy = unit:copy()
		if mechanics:getBattle():isHostile(caster, unit) then
			local amount = math.floor((self.dmg or 0) * n * (100 - lightReduction(unit)) / 100)
			if amount <= 0 or not unit:isAlive() or unit:isInvincible() then return zero end
			local hp, cnt = copy:getAvailableHealth(), copy:getCount()
			copy:damage(amount)
			return { hpDelta = -(hp - copy:getAvailableHealth()), unitsDelta = -(cnt - copy:getCount()) }
		end
		local lvl = ENUM.HealLevel.resurrect
		local okRing, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
		if okRing and ring then lvl = ENUM.HealLevel.heal end
		local healed, raised = copy:heal(math.floor((self.per or 0) * n), lvl, ENUM.HealPower.permanent)
		return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = unit:getCreature() }
	end)
	if ok and result then return result end
	return zero
end

return Script
