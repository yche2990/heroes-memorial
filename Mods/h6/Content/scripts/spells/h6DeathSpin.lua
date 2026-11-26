local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Death Spin (H6 Blade Dancer)
---
--- Cast on an enemy stack: the blade ring flies along the line from the caster to the target, and every stack on the way and on the target hex (friend or foe, the caster excepted)
--- takes one shot's damage (pct%, H3 formula, no counterattack; no extra scaling by the shooter's distance or wall rules).
--- Parameters: pct, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	return mechanics:getBattle():isHostile(caster, unit)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
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
	local main = target[1] and target[1].unit
	if caster == nil or not caster:isAlive() or main == nil then return end
	local a, b = caster:getPosition(), main:getPosition()
	local n = L.hexDistance(a, b)
	local seen, list = {}, {}
	local hexes = L.hexTable(battle)
	for k = 1, n do
		local idx = L.lineIndex(a, b, k)
		local h = idx and hexes[idx]
		if h then
			for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and u:coversPos(h) end)) do
				if u:unitID() ~= caster:unitID() and not seen[u:unitID()] and not u:isInvincible() then
					seen[u:unitID()] = true; list[#list + 1] = u
				end
			end
		end
	end
	if not seen[main:unitID()] then list[#list + 1] = main end
	local total = 0
	for _, u in ipairs(list) do
		if u:isAlive() then
			total = total + (L.hit(server, battle, u, L.attackDamage(server, caster, u, self.pct or 100, true), self.animation, self.sound) or 0)
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { #list, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Death Spin: the ring blade flies along a straight line
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorRay" } -- step number -> cursor
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

--- Hover estimate: same formula as apply. Every stack on the line from the caster to the target and on the target hex (friend or foe, except the caster itself and invulnerable stacks)
--- takes pct% of one shot (expected value, without luck); damage and kills are summed
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if caster == nil or not caster:isAlive() or main == nil then return zero end
		local a, b = caster:getPosition(), main:getPosition()
		local n = L.hexDistance(a, b)
		local seen, list = {}, {}
		local hexes = L.hexTable(battle)
		for k = 1, n do
			local idx = L.lineIndex(a, b, k)
			local h = idx and hexes[idx]
			if h then
				for _, u in ipairs(battle:getUnitsIf(function(u) return L.real(u) and u:coversPos(h) end)) do
					if u:unitID() ~= caster:unitID() and not seen[u:unitID()] and not u:isInvincible() then
						seen[u:unitID()] = true; list[#list + 1] = u
					end
				end
			end
		end
		if not seen[main:unitID()] then list[#list + 1] = main end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(list) do
			if u:isAlive() then
				local d, killed = hcHit(u, hcMeanAttack(caster, u, self.pct or 100, true))
				out.hpDelta, out.unitsDelta = out.hpDelta - d, out.unitsDelta - killed
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
