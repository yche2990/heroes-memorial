local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Savage Charge (H6 Mauler, Brute)
---
--- Choose a hex (straight-line distance within its Speed, where it fits): it charges along the straight line, and every enemy it passes takes
--- pct% of a normal attack as damage (H3 formula, no counterattack), then it stops on that hex. The original "knocks small creatures aside" is not done.
--- Parameters: pct, animation, sound

local function pathUnits(battle, caster, dest)
	local start = caster:getPosition()
	local hexes = L.hexTable(battle)
	local n = L.hexDistance(start, dest)
	local seen, out = {}, {}
	for k = 1, n do
		local idx = L.lineIndex(start, dest, k)
		local h = idx and hexes[idx]
		if h then
			local list = battle:getUnitsIf(function(u) return L.real(u) and u:coversPos(h) end)
			for _, u in ipairs(list) do
				if not seen[u:unitID()] and battle:isHostile(caster, u) then seen[u:unitID()] = true; out[#out + 1] = u end
			end
		end
	end
	return out
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	local caster = mechanics:getUnitCaster()
	local dest = target[1] and target[1].hex
	local battle = mechanics:getBattle()
	if caster == nil or dest == nil or not dest:isValid() or not dest:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	local d = L.hexDistance(caster:getPosition(), dest)
	if d < 1 or d > caster:getBonusesValue({ type = "STACKS_SPEED" }) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	if not battle:isAccessibleForUnit(caster, dest) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local dest = target[1] and target[1].hex
	if caster == nil or not caster:isAlive() or dest == nil then return end
	local victims = pathUnits(battle, caster, dest)
	server:moveUnit(battle, caster, dest, true)
	local total = 0
	for _, u in ipairs(victims) do
		if u:isAlive() then
			total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, false), self.animation, self.sound) or 0)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_CHARGE_H6C", 1, { L.name(caster) }, { #victims, total })
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Savage Charge: charges in a straight line to the target hex, ramming enemies on the way
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorCharge" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
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

--- Hover estimate: same formula as apply. Every enemy stack passed on the way takes pct% of a normal attack (expected value, without luck)
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		local dest = spellTarget and spellTarget[1] and spellTarget[1].hex
		if caster == nil or not caster:isAlive() or dest == nil or not dest:isValid() then return zero end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(pathUnits(battle, caster, dest)) do
			if u:isAlive() then
				local d, killed = hcHit(u, hcMeanAttack(caster, u, self.pct or 100, false))
				out.hpDelta, out.unitsDelta = out.hpDelta - d, out.unitsDelta - killed
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
