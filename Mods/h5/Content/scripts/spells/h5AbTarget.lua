local Base = require("spells/unitEffect")
local L = require("spells/h5AbLib")
local C = L.C
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Status-type active abilities of H5 creatures cast on a stack:
---   mode = "gamble"   Gamble (Djinn Vizier): allies Luck +1-3, enemies Luck -1-3 (random), lasting creature spell power rounds. uses per battle (original 3)
---   mode = "order"    Chieftain's Order (Chieftain): deals Chieftain count x dmgPer damage to an ally, then its Speed +min(Chieftain count x atbPer, atbMax)%
---                     (original: initiative +Chieftain count x 1%, at most 60%), until its next action. Unlimited
---   mode = "sabotage" Sabotage (Gremlin Saboteur): an enemy mechanical creature or war machine is paralyzed for one round (cannot act or retaliate),
---                     requires the gremlins' total health to exceed 1/coef of the target's total health (original coef 10). Unlimited
---   mode = "seduce"   Seduction (Succubus Seducer): controls an enemy stack without mind immunity for Seducer total health / target total health rounds (rounded down, at least 1 needed),
---                     at most maxTurns; the effect is that of Hypnotize (spell). Once per battle
---   mode = "defile"   Magic Hindrance (Goblin Witch-Doctor): an enemy spellcasting stack loses 1 cast, and its spell power is halved for turns rounds (mark H5_DEFILED_H5C).
---                     In the original it can also affect the enemy hero (double mana cost, half power or failed casts); VCMI cannot change hero mana, so not done. Unlimited
---   mode = "random"   Random Magic (Djinn / Djinn Sultan): casts a random spell from the dark list on an enemy; with sultan = true a random spell from the light list on an ally.
---                     Level level, spell power = creature spell power. Unlimited
---   mode = "syphon"   Mana Syphon (Vermin): once per battle. In the original it steals ceil(Vermin count x 0.125) mana from the enemy hero and gives it to own spellcasting stacks;
---                     VCMI cannot change hero mana, so as an approximation: other own spellcasting stacks get +1 cast each, the target (an enemy spellcasting stack) loses 1 cast
---   mode = "manaFeed" Mana Feed (Elder Druid, spell NO_TARGET): in the original it gives all its mana to the hero; as an approximation it hands over its remaining casts (remaining casts become 0, never negative),
---                     and for the rest of the battle the own hero's spell costs drop by the remaining casts (at least 1 per spell); the Elder Druid can no longer cast
--- Parameters: mode, turns, dmgPer, atbPer, atbMax, coef, maxTurns, spell, dark, light, level, uses, mark

local function isCaster(u)
	return u:hasBonuses({ type = "SPELLCASTER" })
end

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) or not unit:isAlive() or unit:isTurret() then return false end
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	local same = not mechanics:getBattle():isHostile(caster, unit)
	local mode = self.mode
	if mode == "gamble" then return true end
	if mode == "order" then return same and unit:unitID() ~= caster:unitID() end
	if mode == "sabotage" then
		if same then return false end
		if not (C.isMechanical(unit) or unit:hasBonuses({ type = "SIEGE_WEAPON" })) then return false end
		return caster:getAvailableHealth() * (self.coef or 10) > unit:getAvailableHealth()
	end
	if mode == "seduce" then
		if same or unit:hasBonuses({ type = "SIEGE_WEAPON" }) or unit:hasBonuses({ type = "HYPNOTIZED" }) then return false end
		if unit:hasBonuses({ type = "MIND_IMMUNITY" }) or not C.isLivingH5(unit) then return false end
		return caster:getAvailableHealth() >= unit:getAvailableHealth()
	end
	if mode == "defile" then return not same and isCaster(unit) end
	if mode == "random" then
		if self.sultan then return true end
		return not same
	end
	if mode == "syphon" then return not same end
	if mode == "manaFeed" then return unit:unitID() == caster:unitID() end
	return false
end

function Script:applicableTarget(mechanics, problem, target)
	-- Mana Feed is cast on itself (spell NO_TARGET)
	if self.mode == "manaFeed" then return mechanics:getUnitCaster() ~= nil end
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	return false
end

local function spellByName(name)
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(name) end)
	if s == nil then pcall(function() s = LIBRARY:getSpellByName(L.MOD .. ":" .. name) end) end
	return s
end

function Script:add(server, battle, unit, desc)
	L.addBonus(server, battle, unit, desc, true)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil and self.mode == "manaFeed" then unit = caster end
	if unit == nil or not unit:isAlive() then return end
	local mode = self.mode
	local n = caster:getCount()
	local numbers = {}
	local anim, sound = self.animation, self.sound
	local turnsDur = function(t) return ENUM.BonusDuration.nTurns, math.max(1, t) end

	-- Round 344: AI simulation branch (ai-skills-design #29 Chieftain's Order). Hitting an ally is vetoed by the AI as an own loss:
	-- in the simulation it does not hit, and only has value on a melee ally that "can only reach an enemy this round after the speed-up": against its nearest enemy 0.3 x one of its attacks - the value of that hit's damage.
	-- Real casts do not go through here
	if mode == "order" and Proxy.trial(server) then
		if unit:isShooter() then return end
		local e, dist = Proxy.nearestHostile(battle, unit)
		if e == nil then return end
		local speed = unit:getBonusesValue({ type = "STACKS_SPEED" })
		local pct = math.min(n * (self.atbPer or 1), self.atbMax or 60)
		if dist - 1 <= speed or dist - 1 > speed * (100 + pct) / 100 then return end
		local hp = 0.3 * Proxy.attackEstimate(unit, e, 100, false)
			- Proxy.costHp(unit, n * (self.dmgPer or 1) / unit:getMaxHealth(), e)
		if hp >= e:getMaxHealth() then Proxy.damage(server, battle, e, hp) end
		return
	end

	-- Round 344: AI simulation branch (ai-skills-design #42 Magic Hindrance, #43 Mana Syphon, #44 Mana Feed). Casts and mana are not (or barely) counted in the AI's estimate,
	-- so it reports: enemy casters at target total health x rounds / 8 x 0.15 (Hindrance 2 rounds, Syphon 1 round);
	-- own extra / handed-over casts booked as stack value x 0.045 x level 2 x casts / 8; all capped as weak abilities. Real casts do not go through here
	if (mode == "defile" or mode == "syphon" or mode == "manaFeed") and Proxy.trial(server) then
		local hp = 0
		local e = unit
		if mode == "defile" or mode == "syphon" then
			if not battle:isHostile(caster, unit) or not isCaster(unit) then return end
			hp = unit:getAvailableHealth() * ((mode == "defile") and (self.turns or 2) or 1) / 8 * 0.15
			if mode == "syphon" then
				for _, f in ipairs(battle:getUnitsIf(function(u)
					return u:isAlive() and not battle:isHostile(caster, u) and u:unitID() ~= caster:unitID() and isCaster(u)
				end)) do
					hp = hp + Proxy.hpOf(Proxy.value(f) * f:getCount() * 0.045 * 2 / 8, unit)
				end
			end
		else
			e = Proxy.nearestHostile(battle, caster)
			if e == nil then return end
			local total, done = 0, C.markValue(caster, "h5ManaCasts") or 0
			pcall(function() total = caster:getBonusesValue({ type = "CASTS" }) end)
			local give = total - done - 1
			if give < 1 then return end
			hp = Proxy.hpOf(Proxy.value(caster) * caster:getCount() * 0.045 * 2 * give / 8, e)
		end
		hp = Proxy.capWeak(hp, battle, caster, e)
		if hp >= e:getMaxHealth() then Proxy.damage(server, battle, e, hp) end
		return
	end

	if mode == "gamble" then
		local v = server:rngInt(1, 3)
		local t = math.max(1, L.sp(caster))
		if battle:isHostile(caster, unit) then v = -v end
		local d, tt = turnsDur(t)
		-- Round 375: when the same stack gets Gamble again the old one is replaced (there was no stacking group, so 3 uses per battle could stack to +/-9 Luck)
		C.removeByStacking(server, battle, unit, "LUCK", "h5AbGamble")
		self:add(server, battle, unit, { type = "LUCK", val = v, duration = d, turns = tt, stacking = "h5AbGamble", sourceType = ENUM.BonusSource.spellEffect,
			sourceID = mechanics:getSpell():getJsonKey(), sourceSecondaryID = mechanics:getEffectLevel() }) -- Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage (log: Unable to find localization); the level is stated
		numbers = { v, tt }
		anim = v > 0 and "h5/fx/Spells_LuckGood" or "h5/fx/Spells_LuckBad"; sound = v > 0 and "FORTUNE" or "MISFORT"
	elseif mode == "order" then
		local dmg = n * (self.dmgPer or 1)
		if dmg > 0 then server:damageUnit(battle, unit, dmg) end
		if unit:isAlive() then
			local pct = math.min(n * (self.atbPer or 1), self.atbMax or 60)
			C.removeByStacking(server, battle, unit, "STACKS_SPEED", "h5AbOrder")
			self:add(server, battle, unit, { type = "STACKS_SPEED", val = pct, valueType = ENUM.BonusValueType.percentToAll,
				duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = "h5AbOrder" })
			numbers = { dmg, pct }
		end
	elseif mode == "sabotage" then
		local d = ENUM.BonusDuration.nTurns
		self:add(server, battle, unit, { type = "NOT_ACTIVE", val = 0, duration = d, turns = 1 })
		self:add(server, battle, unit, { type = "NO_RETALIATION", val = 0, duration = d, turns = 1 })
		C.resetAtb(server, battle, unit)
	elseif mode == "seduce" then
		local t = math.floor(caster:getAvailableHealth() / math.max(1, unit:getAvailableHealth()))
		t = math.max(1, math.min(t, self.maxTurns or 10))
		local spell = spellByName(self.spell or "hypnotize")
		if spell then server:applySpellEffects(battle, caster, spell, { unit }, 3, t, true) end
		numbers = { t }
	elseif mode == "defile" then
		-- Check there are casts left before deducting, never going negative (audit A-6)
		if unit:getBonusesValue({ type = "CASTS" }) > 0 then
			self:add(server, battle, unit, { type = "CASTS", val = -1, hidden = true })
		end
		-- Round 375: hindering the same stack again replaces the old one (each time used to add another 50, summing up to power x100%, x150%, actually strengthening the enemy)
		C.removeByStacking(server, battle, unit, "H5_DEFILED_H5C", "h5AbDefile")
		self:add(server, battle, unit, { type = "H5_DEFILED_H5C", val = 50, duration = ENUM.BonusDuration.nTurns, turns = self.turns or 2, stacking = "h5AbDefile" })
	elseif mode == "random" then
		local list = (not battle:isHostile(caster, unit)) and (self.light or {}) or (self.dark or {})
		if #list > 0 then
			local name
			if Proxy.trial(server) then
				-- Round 375: in the AI simulation random numbers are fixed at the middle value (engine RNGStub), so of the 7 dark spells it always drew the 4th, "Plague",
				-- which is valued low, so the Djinn never cast it. The simulation now uses one representative spell: against enemies Suffering (h5Weakness), for allies the first in the list
				-- (originally: drawn with rngInt in the simulation as well)
				if battle:isHostile(caster, unit) then
					for _, x in ipairs(list) do if x == "h5Weakness" then name = x end end
				end
				name = name or list[1]
			else
				name = list[server:rngInt(1, #list)]
			end
			local spell = spellByName(name)
			if spell and server:describeChanges() then
				server:castSpell(battle, caster, spell, { unit }, L.encoded(self.level or 2, L.sp(caster)))
			elseif spell then
				-- Round 344: in the AI simulation (imaginary battle) castSpell looks up the opposing hero; the engine reported invalid parameters for battleGetFightingHero and the script stopped,
				-- so the AI treated the ability as useless and never cast it; the simulation now uses applySpellEffects to apply only the effects (no hero lookup, duration estimated as 3 rounds),
				-- and errors do not stop it (originally: castSpell was called in the simulation too)
				pcall(function()
					server:applySpellEffects(battle, caster, spell, { unit }, self.level or 2, 3, false)
				end)
			end
		end
	elseif mode == "syphon" then
		local side = caster:getSide()
		local friends = battle:getUnitsIf(function(u)
			return u:isAlive() and not battle:isHostile(caster, u) and u:unitID() ~= caster:unitID() and isCaster(u)
		end)
		for _, f in ipairs(friends) do self:add(server, battle, f, { type = "CASTS", val = 1, hidden = true }) end
		if isCaster(unit) and unit:getBonusesValue({ type = "CASTS" }) > 0 then
			self:add(server, battle, unit, { type = "CASTS", val = -1, hidden = true })
		end
		numbers = { math.ceil(n * 0.125), #friends }
	elseif mode == "manaFeed" then
		-- Remaining casts = total casts - casts used (h5ManaGate records them on h5ManaCasts; Mana Feed itself uses no mana and is not counted).
		-- The engine deducts this cast after the effect (spendMana), so the total is pressed to "used + this one", leaving exactly 0 (adding -100 used to make the total negative and the engine reported ammo overuse)
		local total, done = 0, C.markValue(caster, "h5ManaCasts") or 0
		pcall(function() total = caster:getBonusesValue({ type = "CASTS" }) end)
		local give = math.max(1, total - done - 1)
		if total > done + 1 then
			self:add(server, battle, caster, { type = "CASTS", val = done + 1 - total, hidden = true })
		end
		self:add(server, battle, caster, { type = "CHANGES_SPELL_COST_FOR_ALLY", val = give })
		numbers = { give }
	end

	if server:describeChanges() then
		if anim then server:showBattleAnimation(battle, { { unit = unit } }, anim, sound or "", 1.0, true) end
		server:refreshBattleUnits(battle)
		if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(unit) }, numbers) end
	end
	if mode ~= "manaFeed" then L.useCast(server, battle, caster, "h5AbTarget" .. (mode or ""), self.uses) end
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): H5 status abilities
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local BY_MODE = {
		seduce = { [1] = "kadCursorCharm" },
	}
	local CURSORS = BY_MODE[self.mode or ""] or {  }
	local AIM = { -- target type of the first step (spell targetType)
		["heroes-memorial.h5:h5AbDefileMagic"] = "creature",
		["heroes-memorial.h5:h5AbLuckGambler"] = "creature",
		["heroes-memorial.h5:h5AbManaFeed"] = "nothing",
		["heroes-memorial.h5:h5AbOrderOfTheChief"] = "creature",
		["heroes-memorial.h5:h5AbRandomCastDark"] = "creature",
		["heroes-memorial.h5:h5AbRandomCastDarkLight"] = "creature",
		["heroes-memorial.h5:h5AbSabotage"] = "creature",
		["heroes-memorial.h5:h5AbSeduce"] = "creature",
		["heroes-memorial.h5:h5AbSyphonMana"] = "creature",
	}
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

--- Hover estimate: only Chieftain's Order deals damage on the spot, same formula as apply: allies lose number of chieftains x dmgPer (not adjusted).
--- The spell of Random Magic is drawn only when cast; the other modes do not change health; all return 0
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	if self.mode ~= "order" then return zero end
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local dest = self:filterTarget(mechanics, spellTarget or {})[1]
		local unit = dest and dest.unit
		if unit == nil or not unit:isAlive() then return zero end
		local dmg = math.floor(caster:getCount() * (self.dmgPer or 1))
		if dmg <= 0 then return zero end
		local copy = unit:copy()
		local hp, cnt = copy:getAvailableHealth(), copy:getCount()
		copy:damage(dmg)
		return { hpDelta = -(hp - copy:getAvailableHealth()), unitsDelta = -(cnt - copy:getCount()) }
	end)
	if ok and result then return result end
	return zero
end

return Script
