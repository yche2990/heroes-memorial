--- Frenzy (H6): the target (friend or foe) immediately attacks the nearest other stack (not using its action, no counterattack) with +pct% damage. Parameter: pct (4 numbers)
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function nearest(battle, u)
	local best, bd = nil, 1000
	for _, x in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:unitID() ~= u:unitID() end)) do
		local d = L.unitDistance(u, x)
		if d < bd then best, bd = x, d end
	end
	return best
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local pct = 100 + S.pick(mechanics, self.pct)
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local v = nearest(battle, u)
			if v then
				if Proxy.trial(server) then
					Proxy.damage(server, battle, v, Proxy.attackEstimate(u, v, pct, false), {})
				else
					L.hit(server, battle, v, L.attackDamage(server, u, v, pct, false), nil, nil)
				end
			end
		end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Madness (H6): the target at once attacks the nearest stack
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

--- Hover estimate: same formula as apply. The target at once hits the nearest other stack with a normal attack (damage +pct%), expected value (without luck).
--- Shows the damage and kills on the stack that is hit
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local pct = 100 + S.pick(mechanics, self.pct)
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, dest in ipairs(self:filterTarget(mechanics, spellTarget or {})) do
			local u = dest.unit
			if u and u:isAlive() then
				local v = nearest(battle, u)
				if v then
					local d, killed = hcHit(v, hcMeanAttack(u, v, pct, false))
					out.hpDelta, out.unitsDelta = out.hpDelta - d, out.unitsDelta - killed
				end
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
