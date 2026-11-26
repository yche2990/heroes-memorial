local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Ill Blood (H6 Azkaal, Arebon): cast on an enemy stack. It immediately strikes an adjacent stack for pct% of its normal attack
--- (its own allies first, no counterattack) and loses its action this round. Parameters: pct, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	if not mechanics:getBattle():isHostile(caster, unit) then return false end
	return #L.around(mechanics:getBattle(), unit, function(u) return u:unitID() ~= caster:unitID() end) > 0
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
	if caster == nil or main == nil or not main:isAlive() then return end
	local near = L.around(battle, main, function(u) return u:unitID() ~= caster:unitID() end)
	local victim = nil
	for _, u in ipairs(near) do if not battle:isHostile(main, u) then victim = u; break end end
	victim = victim or near[1]
	if victim then
		local dealt = L.hit(server, battle, victim, L.attackDamage(server, main, victim, self.pct or 105, false), self.animation, self.sound) or 0
		L.log(server, battle, "H6_ILLBLOOD_H6C", 1, { L.name(main), L.name(victim) }, { dealt })
	end
	if main:isAlive() then
		server:addUnitBonus(battle, main, { type = "NOT_ACTIVE", val = 0, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = "h6IllBlood" }, true)
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- 2026-11-07: the engine only gives spell effect scripts hexes as targets, so the stack on the hex is attached (see h6Lib.unitTarget)
function Script:transformTarget(mechanics, aimPoint, spellTarget) return L.unitTarget(mechanics, spellTarget) end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Ill Blood: forces an enemy stack to attack a neighbour (its own allies first)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorCharm" } -- step number -> cursor
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

--- For the hover estimate: expected value of h6Lib.attackDamage (random damage takes the average of min and max, otherwise the same formula: attack/defense modifiers, damage bonuses and reductions, pct%)
local function hcMeanAttack(attacker, target, pct, ranged)
	ranged = ranged == true
	local modifier = L.damageModifier(attacker, target, ranged)
	if modifier <= 0 then return 0 end
	local minDamage = attacker:getMinDamage(ranged)
	local maxDamage = math.max(minDamage, attacker:getMaxDamage(ranged))
	local base = attacker:getCount() * (minDamage + maxDamage) / 2
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * modifier * (pct or 100) / 100))
end

--- For the hover estimate: a copy of L.hit that returns damage, kills (0, 0 when the target cannot be hit or the values are invalid)
local function hcHit(target, amount)
	amount = math.floor(amount or 0)
	if target == nil or not target:isAlive() or target:isGhost() or target:isInvincible() or amount <= 0 then return 0, 0 end
	local copy = target:copy()
	local hp, cnt = copy:getAvailableHealth(), copy:getCount()
	copy:damage(amount)
	return hp - copy:getAvailableHealth(), cnt - copy:getCount()
end

--- Hover estimate: same formula as apply. The target hits one adjacent stack (its own allies first) with pct% of its normal attack, expected value (without luck).
--- Shows the damage and kills on the stack that is hit
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if caster == nil or main == nil or not main:isAlive() then return zero end
		local near = L.around(battle, main, function(u) return u:unitID() ~= caster:unitID() end)
		local victim = nil
		for _, u in ipairs(near) do if not battle:isHostile(main, u) then victim = u; break end end
		victim = victim or near[1]
		if victim == nil then return zero end
		local d, killed = hcHit(victim, hcMeanAttack(main, victim, self.pct or 105, false))
		return { hpDelta = -d, unitsDelta = -killed }
	end)
	if ok and result then return result end
	return zero
end

return Script
