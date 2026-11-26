--- Heal, Mass Heal (H6): friendly stacks regain / resurrect base + per x Spell Power health (permanent);
--- enemy undead, demons and orcs instead take dmgBase + dmgPer x Spell Power Light damage. Parameters: base, per, dmgBase, dmgPer (4 numbers)
--- Extra parameters for class abilities (from batch 2): deadOnly (resurrection: only on corpses of friendly living stacks), noEnemy (cannot target enemies),
---   protect (the resurrected stack cannot act and takes no damage this round), cleanse (dispels all negative spells on the friendly target),
---   speed / speedTurns (friendly target Speed +speed for speedTurns rounds)
local Base = require("spells/unitEffect")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not unit:isAlive() and unit:isGhost() then return false end
	local side = mechanics:getCasterSide()
	if unit:getSide() == side then
		if self.deadOnly then
			return (not unit:isAlive()) and not (unit:hasBonuses({ type = "UNDEAD" }) or unit:hasBonuses({ type = "NON_LIVING" })
				or unit:hasBonuses({ type = "MECHANICAL" }) or unit:hasBonuses({ type = "SIEGE_WEAPON" }))
		end
		return not (unit:hasBonuses({ type = "UNDEAD" }) or unit:hasBonuses({ type = "NON_LIVING" }) or unit:hasBonuses({ type = "MECHANICAL" })
			or unit:hasBonuses({ type = "SIEGE_WEAPON" })) or unit:isAlive()
	end
	if self.noEnemy then return false end
	return unit:isAlive() and S.evil(unit)
end

function Script:applicableGeneral(mechanics, problem)
	if #mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:extras(mechanics, server, battle, u)
	local key = mechanics:getSpell():getJsonKey()
	local lvl = mechanics:getEffectLevel()
	local function add(d)
		d.sourceType = "SPELL_EFFECT"; d.sourceID = key; d.sourceSecondaryID = lvl
		server:addUnitBonus(battle, u, d, false)
	end
	if self.cleanse then
		local neg = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
			local sp = LIBRARY:getSpellByName(b:getSourceID())
			return sp ~= nil and sp:isNegative()
		end)
		if neg:size() > 0 then Proxy.removeExact(server, battle, u, neg) end
	end
	if self.speed and self.speed > 0 then
		add({ type = "STACKS_SPEED", val = self.speed, duration = "N_TURNS", turns = self.speedTurns or 2 })
	end
	if self.protect then
		add({ type = "NOT_ACTIVE", subtype = key, val = 0, duration = "N_TURNS", turns = 1 })
		add({ type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 100, duration = "N_TURNS", turns = 1 })
		add({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.any", val = 100, duration = "N_TURNS", turns = 1 })
	end
end

local function ring(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local side = mechanics:getCasterSide()
	local heal = math.floor(S.value(mechanics, self.base, self.per))
	local dmg = math.floor(S.value(mechanics, self.dmgBase or self.base, self.dmgPer or self.per))
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u then
			if u:getSide() == side then
				local living = not (u:hasBonuses({ type = "UNDEAD" }) or u:hasBonuses({ type = "NON_LIVING" }) or u:hasBonuses({ type = "MECHANICAL" }))
				local level = (living and not ring(u)) and ENUM.HealLevel.resurrect or ENUM.HealLevel.heal
				if u:isAlive() or level == ENUM.HealLevel.resurrect then
					server:healUnit(battle, u, heal, level, ENUM.HealPower.permanent)
					if not Proxy.trial(server) and u:isAlive() then self:extras(mechanics, server, battle, u) end
				end
			elseif u:isAlive() and S.evil(u) then
				local d = S.spellDamage(mechanics, u, dmg, "01lightSchool")
				if Proxy.trial(server) then Proxy.damage(server, battle, u, d, {}) elseif d > 0 then server:damageUnit(battle, u, d) end
			end
		end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Divine Intervention / Heal / Mass Heal / Resurrection (H6)
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

--- Hover estimate: same formula as apply. Friendly stacks: heal / resurrect base + per x Spell Power (living stacks can be resurrected; with the Ring of Oblivion on the field only the top creature is healed);
--- enemy undead, demons and orcs: dmgBase + dmgPer x Spell Power light damage (through the engine's spell damage adjustment).
--- When both apply, only the larger one is shown (the status bar holds one number); when more than one kind of creature is resurrected only the restored health is shown
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local side = mechanics:getCasterSide()
		local healAmt = math.floor(S.value(mechanics, self.base, self.per))
		local dmgAmt = math.floor(S.value(mechanics, self.dmgBase or self.base, self.dmgPer or self.per))
		local heal, raised, damage, kills = 0, 0, 0, 0
		local raisedType, mixed = nil, false
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local u = dest.unit
			if u then
				if u:getSide() == side then
					local living = not (u:hasBonuses({ type = "UNDEAD" }) or u:hasBonuses({ type = "NON_LIVING" }) or u:hasBonuses({ type = "MECHANICAL" }))
					local level = (living and not ring(u)) and ENUM.HealLevel.resurrect or ENUM.HealLevel.heal
					if (u:isAlive() or level == ENUM.HealLevel.resurrect) and healAmt > 0 then
						local h, r = u:copy():heal(healAmt, level, ENUM.HealPower.permanent)
						heal = heal + (h or 0)
						if r and r > 0 then
							raised = raised + r
							local cr = u:getCreature()
							if raisedType == nil then raisedType = cr
							elseif raisedType:getJsonKey() ~= cr:getJsonKey() then mixed = true end
						end
					end
				elseif u:isAlive() and S.evil(u) then
					local d = math.floor(S.spellDamage(mechanics, u, dmgAmt, "01lightSchool") or 0)
					if d > 0 then
						local copy = u:copy()
						local hp, cnt = copy:getAvailableHealth(), copy:getCount()
						copy:damage(d)
						damage = damage + (hp - copy:getAvailableHealth())
						kills = kills + (cnt - copy:getCount())
					end
				end
			end
		end
		if damage > 0 and damage > heal then return { hpDelta = -damage, unitsDelta = -kills } end
		if heal > 0 then
			if raised > 0 and raisedType and not mixed then return { hpDelta = heal, unitsDelta = raised, unitType = raisedType } end
			return { hpDelta = heal, unitsDelta = 0 }
		end
		return zero
	end)
	if ok and result then return result end
	return zero
end

return Script
