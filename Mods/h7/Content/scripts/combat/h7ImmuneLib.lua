--- Heroes VII creatures and spells (heroes-memorial.h7) batch A: helpers shared by negative spell immunities.
--- Only loaded with require("heroes-memorial.h7:combat/h7ImmuneLib"), not registered as a script.
---
--- H7's "X Immunity / Magic Immunity / Pure Aura" only blocks negative statuses (Slow, Curse and the like); damage spells still hit (halved damage is handled by a normal bonus).
--- The engine's NEGATIVE_EFFECTS_IMMUNITY also blocks damage spells, so here there are two layers:
---   1. Blocking in advance: SPELL_IMMUNITY on the stack for the spells in CANDIDATES below that are installed, marked negative, not damage spells, and of a matching school
---      (looked up at runtime with LIBRARY:getSpellByName, reading isNegative / isDamage / getSchools, so listing spells of mods that are not installed causes no error).
---   2. Fallback: when an actively cast (onSpellHit) negative or damage spell lands on it, all effects that spell left are removed at once (as the H5 Magnetic Golem),
---      while the damage still counts. Spells cast with attacks, spell-like attacks and script casts do not send onSpellHit and rely on the list of layer 1.

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}

M.MOD = "heroes-memorial.h7"
M.MARK = "H7_AURA_MARK_H7C"

local D = ENUM.BonusDuration

--- Candidates: negative status spells of the core, the dependency chain (tears-of-ashan / highlands-town) and this mod's H7 spells.
--- Negativity, damage and school are checked again at runtime.
M.CANDIDATES = {
	-- Core
	"slow", "curse", "weakness", "sorrow", "misfortune", "blind", "berserk", "hypnotize", "forgetfulness", "disruptingRay",
	-- Dependency chain
	"tears-of-ashan:agingTOA", "tears-of-ashan:diseaseTOA", "tears-of-ashan:forbearance",
	"highlands-town:iceFrozen",
	-- H7 spells (this mod's spell batches, ids h7<English name>)
	"h7Entangle", "h7Blizzard", "h7Despair", "h7Weakness", "h7Purge", "h7Agony", "h7WaspSwarm", "h7PoisonSpray",
	"h7PoisonCloud", "h7HauntingPlague", "h7TimeControl", "h7TimeStasis", "h7FogShroud", "h7LightningBurst", "h7Frenzy",
	"h7SunBeam", "h7FrostBolt", "h7CircleOfWinter", "h7Implosion",
}

--- The 8 former Prime spells (now in the four schools: Air Time Control/Fortune, Water Teleport/Dispel, Earth Implosion/Time Stasis, Fire Summon Elemental/Soul Fire)
M.PRIME = { "h7TimeControl", "h7Fortune", "h7Teleport", "h7DispelMagic", "h7Implosion", "h7SummonElemental",
	"h7TimeStasis", "h7SoulConflagration" }

--- Slowing spells (blocked in advance by Unfettered): core Slow is already written as SPELL_IMMUNITY in the creature JSON; the rest are added here
M.SLOWS = { "slow", "h7Entangle", "h7Blizzard", "the-great-expansion:anchor", "tarnum.tarnumdriter:tBlizzard",
	"tidesofwar:mdtBind", "ruins-town:rn_seaweedGrapple" }

local SCHOOL_ALIAS = { light = "01lightSchool", dark = "02darkSchool", darkness = "02darkSchool" }

local cache = {}

--- Find a spell by name: try the original name and this mod's prefix; nil if not found
function M.resolve(name)
	if name == nil or name == "" then return nil end
	if cache[name] ~= nil then return cache[name] or nil end
	local s = nil
	pcall(function() s = LIBRARY:getSpellByName(name) end)
	if s == nil and not string.find(name, ":", 1, true) then
		pcall(function() s = LIBRARY:getSpellByName(M.MOD .. ":" .. name) end)
	end
	if s == nil then
		-- The bonus source id may be written as "spell.xxx"
		local short = string.match(name, "^spell%.(.+)$")
		if short then pcall(function() s = LIBRARY:getSpellByName(short) end) end
	end
	cache[name] = s or false
	return s
end

--- Subtype form of a spell for SPELL_IMMUNITY / MORE_DAMAGE_FROM_SPELL ("spell.slow", "mod:spell.xxx")
function M.subtype(spell)
	local k = spell:getJsonKey()
	local mod, nm = string.match(k, "^(.*):([^:]+)$")
	if mod == nil or mod == "core" then return "spell." .. (nm or k) end
	return mod .. ":spell." .. nm
end

local function short(id)
	id = tostring(id or "")
	return string.match(id, "([^:%.]+)$") or id
end
M.short = short

function M.sameSpell(sourceId, spell)
	if sourceId == nil or spell == nil then return false end
	return short(sourceId) == short(spell:getJsonKey())
end

local function schoolKeys(spell)
	local out = {}
	local ok, list = pcall(function() return spell:getSchools() end)
	if not ok or list == nil then return out end
	for _, sc in ipairs(list) do
		local k = nil
		pcall(function() k = sc:getJsonKey() end)
		if k then table.insert(out, short(k)) end
	end
	return out
end

--- school: fire / water / earth / air / light / dark / 01lightSchool / 02darkSchool; "any" = any school
function M.inSchool(spell, school)
	local keys = schoolKeys(spell)
	if school == "any" then return #keys > 0 end
	local want = SCHOOL_ALIAS[school] or school
	for _, k in ipairs(keys) do
		if k == want then return true end
	end
	return false
end

local listCache = {}

--- Installed candidate spells that are negative, not damage spells, and of a matching school
function M.debuffs(school)
	if listCache[school] then return listCache[school] end
	local out = {}
	for _, name in ipairs(M.CANDIDATES) do
		local s = M.resolve(name)
		if s ~= nil and s:isNegative() and not s:isDamage() and M.inSchool(s, school) then table.insert(out, s) end
	end
	listCache[school] = out
	return out
end

--- Installed spells in a list (school ignored; with negativeOnly only negative ones)
function M.existing(names, negativeOnly)
	local out = {}
	for _, name in ipairs(names) do
		local s = M.resolve(name)
		if s ~= nil and (not negativeOnly or s:isNegative()) then table.insert(out, s) end
	end
	return out
end

local function marked(unit, key)
	return unit:getBonuses({ type = M.MARK }):filter(function(b) return b:getStacking() == key end):size() > 0
end

--- Add a set of SPELL_IMMUNITY to a stack (stacking key, not added again if present); extra holds additional bonus descriptors (also with key)
function M.ensure(server, battle, unit, key, spells, src, extra)
	if marked(unit, key) then return end
	src = src or unit:getCreature():getJsonKey()
	for _, s in ipairs(spells) do
		server:addUnitBonus(battle, unit, {
			type = "SPELL_IMMUNITY", subtype = M.subtype(s), val = 0, hidden = true,
			duration = D.oneBattle, sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key
		}, true)
	end
	for _, e in ipairs(extra or {}) do
		e.duration = e.duration or D.oneBattle
		e.sourceType = e.sourceType or ENUM.BonusSource.other
		e.sourceID = e.sourceID or src
		e.stacking = key
		e.hidden = true
		server:addUnitBonus(battle, unit, e, true)
	end
	server:addUnitBonus(battle, unit, {
		type = M.MARK, val = 1, hidden = true, duration = D.oneBattle,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = key
	}, true)
end

function M.clear(server, battle, unit, key)
	for _, t in ipairs({ "SPELL_IMMUNITY", "MORE_DAMAGE_FROM_SPELL", M.MARK }) do
		local list = unit:getBonuses({ type = t }):filter(function(b) return b:getStacking() == key end)
		if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
	end
end

--- Remove all effects a given spell left on a stack; returns how many were removed
function M.stripSpell(server, battle, unit, spell)
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		return M.sameSpell(b:getSourceID(), spell)
	end)
	local n = list:size()
	if n > 0 then server:removeUnitBonuses(battle, unit, list) end
	return n
end

--- Remove the effects of all negative spells of a school (used when Fire Aura is applied)
function M.stripSchool(server, battle, unit, school)
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	local rm = {}
	for i = 1, list:size() do
		local sid = list:getBonus(i):getSourceID()
		if sid ~= nil and rm[sid] == nil then
			local s = M.resolve(sid)
			rm[sid] = (s ~= nil and s:isNegative() and M.inSchool(s, school)) and true or false
		end
	end
	local sel = list:filter(function(b) return rm[b:getSourceID()] == true end)
	if sel:size() > 0 then server:removeUnitBonuses(battle, unit, sel) end
end

--- Fallback: whether the effects this spell left should be removed when it lands on a stack that is "only immune to negative statuses"
function M.shouldStrip(spell, school)
	if spell == nil or spell:isPositive() then return false end
	if not (spell:isNegative() or spell:isDamage()) then return false end
	if school == nil then return true end
	return M.inSchool(spell, school)
end

--- Fallback: in the list (ids)
function M.inNames(spell, names)
	for _, n in ipairs(names) do
		if short(n) == short(spell:getJsonKey()) then return true end
	end
	return false
end

return M
