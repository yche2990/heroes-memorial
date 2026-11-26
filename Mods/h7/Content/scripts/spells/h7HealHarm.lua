local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local C = require("heroes-memorial:combat/h5Common")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Heal (H7): allies (the caster's stacks) are healed and resurrected (permanently), enemy undead take Light damage; no effect on constructs (non-living, mechanical, undead excepted).
--- Advanced (with Light Understanding I) 4x4 area (range in the spell json), friend and foe: allies in the area are healed, enemy undead damaged, the rest unaffected.
--- The spell json has smart = false; friend and foe are told apart here.
---
--- Parameters:
---   heal, healPer    healing = heal[mastery] + healPer[mastery] x Spell Power, plus the hero's spell bonus
---   dmg, dmgPer      damage to undead = dmg[mastery] + dmgPer[mastery] x Spell Power (average of the H7 random range), then the engine's spell damage adjustments
---   exclude          bonus types not affected (undead excepted)

local function has(u, t) return Lib.has(u, t) end

function Script:isFriend(mechanics, unit)
	return unit:getSide() == mechanics:getCasterSide()
end

function Script:construct(unit)
	if has(unit, "UNDEAD") then return false end
	for _, t in ipairs(self.exclude or { "NON_LIVING", "MECHANICAL", "SIEGE_WEAPON" }) do
		if has(unit, t) then return true end
	end
	return false
end

function Script:isValidTarget(mechanics, unit)
	if self:construct(unit) then return false end
	if self:isFriend(mechanics, unit) then
		if not unit:isValidTarget(true) then return false end
		if unit:getTotalHealth() <= unit:getAvailableHealth() then return false end
		if unit:isDead() then
			-- Cannot resurrect if another stack or an obstacle lies on the corpse
			local hexes = unit:getHexes()
			for i = 1, hexes:size() do
				local hex = hexes:at(i)
				local blockers = mechanics:getBattle():getUnitsIf(function(o)
					return o:unitID() ~= unit:unitID() and o:isValidTarget(false) and o:coversPos(hex)
				end)
				if #blockers > 0 then return false end
				if #mechanics:getBattle():getObstaclesOnPos(hex, true) > 0 then return false end
			end
		end
		return true
	end
	return unit:isValidTarget(false) and has(unit, "UNDEAD")
end

function Script:isReceptive(mechanics, unit)
	if self:isFriend(mechanics, unit) then
		return not unit:hasAbsoluteImmunity(mechanics:getSpell())
	end
	if unit:isInvincible() then return false end
	return mechanics:isReceptive(unit)
end

function Script:healAmount(mechanics, unit)
	local raw = Lib.value(self.heal, self.healPer, Lib.level(mechanics), Lib.power(mechanics))
	return mechanics:applySpellBonus(math.floor(raw), unit)
end

function Script:damageAmount(mechanics, unit)
	local raw = Lib.value(self.dmg, self.dmgPer, Lib.level(mechanics), Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
	return Lib.adjust(mechanics, unit, raw)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local describe = server:describeChanges()
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit then
			if self:isFriend(mechanics, unit) then
				local amount, level = C.reviveHeal(unit, self:healAmount(mechanics, unit))
				if amount > 0 then
					local _, raised = server:healUnit(battle, unit, amount, level, ENUM.HealPower.permanent)
					if raised and raised > 0 and describe then
						server:appendLog(battle, {
							append         = { raised == 1 and "core.genrltxt.117" or "core.genrltxt.116" },
							replaceStrings = { unit:getCreature():getNameTextID(raised) },
							replaceNumbers = { raised }
						})
					end
				end
			elseif unit:isAlive() then
				local dmg, killed = server:damageUnit(battle, unit, self:damageAmount(mechanics, unit))
				if describe and dmg > 0 then
					BattleLog.spellDamage(server, battle, mechanics:getSpell(), unit, dmg, killed)
				end
			end
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Heal (H7): heal and resurrect allies
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

--- Hover estimate: same formula as apply. Allies heal healAmount and can be resurrected (with the Ring of Oblivion on the field only the top creature is healed); enemy undead take damageAmount.
--- When both are in range only the larger one is shown (the status bar holds one number); when more than one kind of creature is resurrected only the restored health is shown
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local heal, raised, damage, kills = 0, 0, 0, 0
		local raisedType, mixed = nil, false
		for _, dest in ipairs(spellTarget or {}) do
			local unit = dest.unit
			if unit and self:isValidTarget(mechanics, unit) and self:isReceptive(mechanics, unit) then
				local copy = unit:copy()
				if self:isFriend(mechanics, unit) then
					local amount, level = C.reviveHeal(unit, self:healAmount(mechanics, unit))
					if amount > 0 then
						local h, r = copy:heal(math.floor(amount), level, ENUM.HealPower.permanent)
						heal = heal + (h or 0)
						if r and r > 0 then
							raised = raised + r
							local cr = unit:getCreature()
							if raisedType == nil then raisedType = cr
							elseif raisedType:getJsonKey() ~= cr:getJsonKey() then mixed = true end
						end
					end
				elseif unit:isAlive() then
					local hp, n = copy:getAvailableHealth(), copy:getCount()
					copy:damage(self:damageAmount(mechanics, unit))
					damage = damage + (hp - copy:getAvailableHealth())
					kills = kills + (n - copy:getCount())
				end
			end
		end
		if damage > 0 and damage > heal then
			return { hpDelta = -damage, unitsDelta = -kills }
		end
		if heal > 0 then
			if raised > 0 and raisedType and not mixed then
				return { hpDelta = heal, unitsDelta = raised, unitType = raisedType }
			end
			return { hpDelta = heal, unitsDelta = 0 }
		end
		return zero
	end)
	if ok and result then return result end
	return zero
end

return Script
