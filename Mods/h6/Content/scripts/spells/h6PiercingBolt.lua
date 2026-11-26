local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Piercing Bolt (H6 Arbalester): cast on an enemy stack. The bolt flies from the shooter through the target all the way to the edge of the battlefield,
--- and every stack on the line (friend or foe, the shooter excepted) takes one normal shot's damage x pct%, with no counterattack.
--- status / statusTurns (round 352, Breeder Mother "Impale"): status spell and rounds applied to enemies hit.
--- logType / logIndex: which battle log line to use (default: Piercing Bolt's).
--- Parameters: pct (default 100), status, statusTurns, logType, logIndex, uses, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	return unit:isAlive() and not unit:isGhost() and not unit:isTurret() and mechanics:getBattle():isHostile(caster, unit)
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isShooter() then
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

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

--- Stacks on the line (nearest first, once each)
function Script:victims(battle, caster, unit)
	local from, to = caster:getPosition(), unit:getPosition()
	local hexes = L.hexTable(battle)
	local seen, list = { [caster:unitID()] = true }, {}
	for k = 1, 40 do
		local idx = L.lineIndex(from, to, k)
		if idx == nil then break end
		local h = hexes[idx]
		local u = h and battle:getUnitByPos(h, true)
		if u ~= nil and not seen[u:unitID()] and u:isAlive() and not u:isGhost() and not u:isTurret() then
			seen[u:unitID()] = true
			list[#list + 1] = u
		end
	end
	if not seen[unit:unitID()] then table.insert(list, 1, unit) end
	return list
end

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	local caster = mechanics:getUnitCaster()
	local dest = spellTarget and spellTarget[1]
	if caster == nil or dest == nil or dest.unit == nil then return hexes end
	for _, u in ipairs(self:victims(mechanics:getBattle(), caster, dest.unit)) do
		local hs = u:getHexes()
		for i = 1, hs:size() do hexes:insert(hs:at(i)) end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	if dest == nil or dest.unit == nil then return end
	local total, count = 0, 0
	for _, u in ipairs(self:victims(battle, caster, dest.unit)) do
		if u:isAlive() and not u:isInvincible() then
			local dmg = L.attackDamage(server, caster, u, self.pct or 100, true)
			local dealt = L.hit(server, battle, u, dmg, self.animation, self.sound)
			total = total + dealt
			count = count + 1
			if self.status and u:isAlive() and battle:isHostile(caster, u) then
				local sp = L.spell(self.status)
				if sp then server:applySpellEffects(battle, caster, sp, { u }, 3, self.statusTurns or 1, false) end
			end
		end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, self.logType or "H6_PIERCING_BOLT_H6C", self.logIndex or 1, { L.name(caster) }, { count, total })
	L.useCast(server, battle, caster, self.key or "h6PiercingBolt", self.uses)
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Piercing Bolt, Lunge: pierce in a straight line to the edge of the battlefield
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

--- Hover estimate: same formula as apply. From the shooter through the target to the edge of the battlefield, every stack on the line (friend or foe) takes pct% of one shot
--- (expected value, without luck); damage and kills are summed; attached status spells are not counted
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		if first == nil or first.unit == nil then return zero end
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(self:victims(battle, caster, first.unit)) do
			if u:isAlive() and not u:isInvincible() then
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
