--- H5 Creatures and Magic: small helpers shared by the spell effect scripts (not registered as a script, required by h5Damage, h5Timed etc.)
---
--- Spell power (SP):
---   Hero casts: the hero's Spell Power (mechanics:getEffectPower()).
---   Creature casts: the H5 creature formula SP = trunc(21*log10(1 + N/G) - 1), N the stack count, G that creature's H5 weekly growth
---             (hidden bonus H5_GROWTH_H5C on the creature). At least 0.
---   Casts triggered by abilities (with attacks, or cast by active ability scripts with server:castSpell): the effect value is written as 1000000 + level*100000 + SP,
---             and the fixed SP and level are decoded here (e.g. Blinding Attack: SP 8, Basic).
--- Neutral Water Elemental and Mummy casts deal only 30% damage (hidden bonus H5_SPELLDMG30_H5C).

local Lib = {}

local ENCODED = 1000000

function Lib.unitSP(unit)
	if not unit then return 0 end
	local g = unit:getBonusesValue({ type = "H5_GROWTH_H5C" })
	if not g or g <= 0 then
		local ok, cg = pcall(function() return unit:getCreature():getGrowth() end)
		g = (ok and cg and cg > 0) and cg or 1
	end
	local n = unit:getCount()
	if n <= 0 then return 0 end
	local sp = math.floor(21 * math.log(1 + n / g, 10) - 1)
	if sp < 0 then sp = 0 end
	return sp
end

local function encoded(mechanics)
	if mechanics:getHeroCaster() then return nil end
	local v = mechanics:getEffectValue() or 0
	if v >= ENCODED then
		local rest = v - ENCODED
		return math.floor(rest / 100000), rest % 100000
	end
	return nil
end

--- Returns the SP of the cast
function Lib.power(mechanics)
	if mechanics:getHeroCaster() then
		return mechanics:getEffectPower()
	end
	local _, sp = encoded(mechanics)
	if sp then return sp end
	local u = mechanics:getUnitCaster()
	sp = Lib.unitSP(u)
	if u then
		-- Sky Daughter Blood Rage level 2/3: spell power x2 / x4 (the largest one counts)
		local mult = 1
		local ok, list = pcall(function() return u:getBonuses({ type = "H5_SPELLPOWER_MULT_H5C" }) end)
		if ok and list then
			for i = 1, list:size() do
				local v = list:getBonus(i):getVal()
				if v > mult then mult = v end
			end
		end
		sp = sp * mult
		-- Goblin Witch-Doctor's Magic Hindrance: cast power reduced to val%
		local d = u:getBonusesValue({ type = "H5_DEFILED_H5C" })
		if d and d > 0 then sp = math.floor(sp * d / 100) end
	end
	return sp
end

--- Returns the mastery level of the cast, 0..3
function Lib.level(mechanics)
	local lvl = encoded(mechanics)
	if lvl then return math.max(0, math.min(3, lvl)) end
	return math.max(0, math.min(3, mechanics:getEffectLevel()))
end

--- Creature cast damage factor (30% for neutrals)
function Lib.casterDamageFactor(mechanics)
	if mechanics:getHeroCaster() then return 1 end
	local u = mechanics:getUnitCaster()
	if u and u:getBonusesValue({ type = "H5_SPELLDMG30_H5C" }) > 0 then
		return u:getBonusesValue({ type = "H5_SPELLDMG30_H5C" }) / 100
	end
	return 1
end

--- base + perPower * SP by level
function Lib.value(base, per, level, sp)
	local b = base and (base[level + 1] or base[#base]) or 0
	local p = per and (per[level + 1] or per[#per]) or 0
	return b + p * sp
end

--- Duration: trunc(base + per*SP), at least 1
function Lib.duration(durBase, durPer, level, sp)
	if not durBase and not durPer then return nil end
	local d = math.floor(Lib.value(durBase, durPer, level, sp))
	if d < 1 then d = 1 end
	return d
end

--- Adjusts the original H5 damage by the engine's spell damage flow (school reduction, magic reduction, vulnerability, the hero's spell bonus etc.).
--- The engine can only adjust the mechanics' own effect value, so the ratio "after / before adjustment" is used.
function Lib.adjust(mechanics, unit, raw)
	local ev = mechanics:getEffectValue() or 0
	if ev <= 0 then return math.floor(raw) end
	local adj = mechanics:adjustEffectValue(unit)
	return math.floor(raw * adj / ev)
end

--- Target filter: requireAny = { "UNDEAD", ... } at least one; exclude = { ... } none at all
local function has(unit, t)
	local ok, r = pcall(function() return unit:hasBonuses({ type = t }) end)
	return ok and r
end
Lib.has = has

function Lib.passesFilter(unit, requireAny, exclude)
	if exclude then
		for _, t in ipairs(exclude) do
			if has(unit, t) then return false end
		end
	end
	if requireAny and #requireAny > 0 then
		for _, t in ipairs(requireAny) do
			if has(unit, t) then return true end
		end
		return false
	end
	return true
end

Lib.ENCODED = ENCODED

return Lib
