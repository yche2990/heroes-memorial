--- H6 Dynasty Weapons: small helpers shared by the scripts (not registered as a script, required by the spell effect and combat event scripts)
---
--- Once per battle / cooldown: dynasty weapon active abilities are special spells cast by the hero (the weapon gives a SPELL bonus; no spellbook needed, no mana cost).
--- After casting, a hidden bonus H6DYN_ONCE is attached to the battlefield (BattleInfo), val = ability id x 10 + casting side (0/1).
--- Battlefield bonuses pass to all stacks of both sides, so reading it on any stack tells whether it was used.
--- Cooldown (Staff of Purification, Blade of Vengeance, Crystal Rose Staff, Nameless Staff): the same bonus is attached to stacks as N_TURNS and vanishes when the cooldown runs out.

local Lib = {}

Lib.MOD = "heroes-memorial.dynasty-weapons"
local ONCE = "H6DYN_ONCE"

function Lib.code(side, index)
	return index * 10 + (side or 0)
end

function Lib.usedBySide(battle, side, index)
	local code = Lib.code(side, index)
	local found = false
	-- The predicate is also called for dead stacks (not in the result), so a side effect is used to go through all stacks
	battle:getUnitsIf(function(u)
		if not found then
			local list = u:getBonuses({ type = ONCE })
			for i = 1, list:size() do
				if list:getBonus(i):getVal() == code then found = true; break end
			end
		end
		return false
	end)
	return found
end

function Lib.used(mechanics, index)
	return Lib.usedBySide(mechanics:getBattle(), mechanics:getCasterSide() or 0, index)
end

--- cooldown = 0: cannot be used again this battle (mark on the battlefield, inherited by both sides);
--- cooldown > 0: usable again after cooldown more rounds following the round of casting. The battlefield's own bonuses do not count down by rounds (BattleInfo::nextRound only handles stacks),
--- so the cooldown mark is attached to every living stack at that time (N_TURNS), and it counts as on cooldown while any stack still has it.
function Lib.markUsed(mechanics, server, index, cooldown)
	local code = Lib.code(mechanics:getCasterSide() or 0, index)
	local d = {
		type       = ONCE,
		val        = code,
		duration   = "ONE_BATTLE",
		sourceType = "OTHER",
		stacking   = "h6dynOnce" .. code,
		hidden     = true
	}
	local battle = mechanics:getBattle()
	if cooldown and cooldown > 0 then
		d.duration = "N_TURNS"
		d.turns = cooldown + 1
		for _, u in ipairs(battle:getUnitsIf(function(u) return u:isAlive() end)) do
			server:addUnitBonus(battle, u, d, false)
		end
		return
	end
	server:addBattleBonus(battle, d)
end

--- With the Ring of Oblivion (HotA) in play, resurrection effects only heal, no resurrection (checklist section 10); without HotA the type does not exist, guarded by pcall
function Lib.ringOfOblivion(unit)
	local ok, v = pcall(function() return unit:getBonusesValue({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and v and v > 0
end

--- Copies a bonus description (table in json form), fills in default duration and source, and adds it to the stack
function Lib.addBonus(server, battle, unit, b, sourceType, sourceID, cumulative, extra)
	local d = {}
	for k, v in pairs(b) do d[k] = v end
	for k, v in pairs(extra or {}) do if d[k] == nil then d[k] = v end end
	if d.turns and d.turns > 0 and not d.duration then d.duration = "N_TURNS" end
	d.duration = d.duration or "ONE_BATTLE"
	d.sourceType = d.sourceType or sourceType or "SPELL_EFFECT"
	if d.sourceID == nil and sourceID ~= nil then d.sourceID = sourceID end
	-- Round 339: since engine 89ce99f1, omitting the casting level means "any level", and looking at a stack's spell status reads the description with that level out of range, giving garbage (log: Unable to find localization); the level is stated
	if d.sourceSecondaryID == nil and (d.sourceType == "SPELL_EFFECT" or d.sourceType == ENUM.BonusSource.spellEffect) then d.sourceSecondaryID = 0 end
	server:addUnitBonus(battle, unit, d, cumulative and true or false)
end

--- Hidden counter: set the value of a hidden bonus to v (remove, then add)
function Lib.setCounter(server, battle, unit, bonusType, v)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if v ~= 0 then
		server:addUnitBonus(battle, unit, {
			type = bonusType, val = v, duration = "ONE_BATTLE", sourceType = "OTHER", hidden = true
		}, false)
	end
end

--- Bonuses on the stack with stacking tag
function Lib.byStacking(unit, filter, tag)
	return unit:getBonuses(filter):filter(function(b) return b:getStacking() == tag end)
end

--- The "strongest" stack: by AI value x count
function Lib.strongest(units)
	local best, bv = nil, -1
	for _, u in ipairs(units) do
		local v = u:getCreature():getAIValue() * u:getCount()
		if v > bv then best, bv = u, v end
	end
	return best
end

--- Total health of the stack at battle start (starting count x health per creature)
function Lib.initialHealth(unit)
	return unit:getBaseAmount() * unit:getMaxHealth()
end

--- Description parameters (registered in stringRegistrations, values are text ids) -> the bonus's description / icon
function Lib.textOf(script)
	local e = {}
	if script.text then e.description = "@" .. script.text end
	if script.icon then e.icon = script.icon end
	return e
end

function Lib.opposite(side)
	return 1 - (side or 0)
end

function Lib.anim(server, battle, unit, anim)
	if anim and anim ~= "" and unit then
		server:showBattleAnimation(battle, { { unit = unit } }, anim, "", 1.0, true)
		return true
	end
	return false
end

--- Cumulative bonuses (Soul of the Wolf, Dust to Dust, damage record of Thorn of Regret): read the old value of stacking group tag, remove it, add back the total.
--- The engine takes only one bonus per stacking group (regardless of mod), so simply adding another does not accumulate.
function Lib.addTotal(server, battle, unit, d, tag)
	local filter = { type = d.type }
	if d.subtype then filter.subtype = d.subtype end
	local old = Lib.byStacking(unit, filter, tag)
	local total = d.val or 0
	for i = 1, old:size() do total = total + old:getBonus(i):getVal() end
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	local n = {}
	for k, v in pairs(d) do n[k] = v end
	n.val = total
	n.stacking = tag
	server:addUnitBonus(battle, unit, n, false)
	return total
end

--- Capital guardians (from other mods): the creature config carries a hidden LUCK 0 whose stacking group starts with "kadGuardian"
function Lib.isGuardian(unit)
	local list = unit:getBonuses({ type = "LUCK" })
	for i = 1, list:size() do
		local s = list:getBonus(i):getStacking()
		if s and s:sub(1, 11) == "kadGuardian" then return true end
	end
	return false
end

function Lib.isSiege(unit)
	return unit:hasBonuses({ type = "SIEGE_WEAPON" })
end

--- Summoned creatures (checklist: always use copy():isSummoned())
function Lib.isSummoned(unit)
	return unit:copy():isSummoned()
end

--- Stacks unaffected by control effects (Loss of Control, Seduction, Web, Time Stasis): mind-immune stacks, commanders, war machines, capital guardians (checklist section 11).
--- "Mind immunity" follows the targetCondition of the core mind spells (Berserk, Hypnotize): MIND_IMMUNITY, undead, non-living and mechanical all count
local MIND = { "MIND_IMMUNITY", "UNDEAD", "NON_LIVING", "MECHANICAL" }
function Lib.mindImmune(unit)
	for _, t in ipairs(MIND) do
		if unit:hasBonuses({ type = t }) then return true end
	end
	return false
end

function Lib.controlImmune(unit)
	return Lib.mindImmune(unit) or unit:isCommander() or Lib.isSiege(unit) or Lib.isGuardian(unit)
end

--- "Already restored this hit" mark (review A5, 2026-11-08). The convention is exactly the same as combat/h6Lib of heroes-memorial.h6 (healedValue section); the two mods rely only on the string convention and do not depend on each other:
---   * Mark: a hidden bonus on the target of type MEMORIAL_MARK, stacking "h6Healed|<attacker stack id>",
---     value = health already restored for this attack, lasting 1 round (as a fallback).
---   * Scripts that "restore damage after the hit" (this mod's h6dynShield; the H6 memorial's h6SpShieldAbsorb, h6SpSacrificeLink, h6Impervious, h6MmFeignHit)
---     only handle entry.damage - already restored in onAfterAttacked, then add the amount they restored to the mark; together they restore at most one share of the same hit.
---   * The onBeforeAttacked of these scripts all clear the "h6Healed|" marks on the target (reset before every attack).
---   * Spell damage (onSpellHit) uses no mark: it is worked out from unitBefore and current health, so what earlier scripts restored is already deducted.
--- Marks are removed with lib/kadAiProxy (removeExact; the engine removes bonuses ignoring the stacking group, which would also remove others' MEMORIAL_MARK with the same value)
local Proxy = require("lib/kadAiProxy")
Lib.HEALED = "h6Healed|"

local function healedKey(other)
	return Lib.HEALED .. tostring(other and other:unitID() or -1)
end

function Lib.healedValue(unit, other)
	local list = Lib.byStacking(unit, { type = "MEMORIAL_MARK" }, healedKey(other))
	local v = 0
	for i = 1, list:size() do v = v + list:getBonus(i):getVal() end
	return v
end

function Lib.unhealed(unit, other, damage)
	return math.max(0, (damage or 0) - Lib.healedValue(unit, other))
end

function Lib.addHealed(server, battle, unit, other, amount)
	if amount == nil or amount <= 0 then return end
	local key = healedKey(other)
	local total = Lib.healedValue(unit, other) + amount
	local list = Lib.byStacking(unit, { type = "MEMORIAL_MARK" }, key)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
	server:addUnitBonus(battle, unit, {
		type = "MEMORIAL_MARK", val = total, duration = "N_TURNS", turns = 1, sourceType = "OTHER",
		sourceID = unit:getCreature():getJsonKey(), stacking = key, hidden = true
	}, true)
end

function Lib.clearHealed(server, battle, unit)
	local list = unit:getBonuses({ type = "MEMORIAL_MARK" }):filter(function(b)
		return string.sub(b:getStacking(), 1, #Lib.HEALED) == Lib.HEALED
	end)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

--- Heavenly Armor / Frost Armor: absorb with the shield first, return the damage still to be dealt
local SHIELD_ON, SHIELD_LEFT = "H6DYN_SHIELD_ON", "H6DYN_SHIELD_LEFT"
function Lib.absorb(server, battle, unit, amount)
	if amount <= 0 or unit:getBonusesValue({ type = SHIELD_ON }) <= 0 then return amount, 0 end
	local left = unit:getBonusesValue({ type = SHIELD_LEFT })
	local absorbed = math.min(amount, left)
	if absorbed <= 0 then return amount, 0 end
	Lib.setCounter(server, battle, unit, SHIELD_LEFT, left - absorbed)
	if left - absorbed <= 0 then
		server:removeUnitBonuses(battle, unit, unit:getBonuses({ type = SHIELD_ON }))
	end
	return amount - absorbed, absorbed
end

--- All damage dealt by this mod's scripts goes through here: shield first, then damageUnit
function Lib.damage(server, battle, unit, amount)
	local rest = Lib.absorb(server, battle, unit, amount)
	if rest <= 0 then return 0, 0 end
	return server:damageUnit(battle, unit, rest)
end

--- Fixed and percentage damage is settled as spell damage: school reduction, protection spells, per-spell vulnerability, invincibility, the hero's spell damage bonus (engine adjustRawDamage).
--- actor: a stack of the casting side (through which the hero's bonus is found); the raw value is used if none is found
function Lib.spellDamage(mechanics, spell, unit, raw)
	if raw <= 0 then return 0 end
	local battle = mechanics:getBattle()
	local actor = mechanics:getUnitCaster()
	if not actor then
		local side = mechanics:getCasterSide()
		for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and not x:isTurret() end)) do actor = u; break end
	end
	if not actor then return raw end
	return spell:adjustDamage(battle, actor, unit, raw)
end

--- Round 316t: original Heroes 6 battlefield statuses (heroes-memorial:h6Chilled / h6Frozen / h6Soaked / h6Dazed,
--- shared by the Dynasty Weapons and the H6 memorial). Cast as spells: immunity, original icon, effect animation and tint are all handled by the engine through that spell.
--- Without caster, any living stack of the side opposite the target is used (the target itself if none); status values are fixed and do not depend on the caster.
function Lib.status(server, battle, target, name, caster)
	if not target or not target:isAlive() or not name or name == "" then return end
	if not server:describeChanges() then return end   -- Not cast during the AI simulation (checklist: Lua skips the AI simulation with describeChanges)
	local sp = LIBRARY:getSpellByName("kad-mechanics:" .. name)
	if not sp then return end
	if caster == nil or not caster:isAlive() then
		local side = target:getSide()
		local others = battle:getUnitsIf(function(x) return x:getSide() ~= side and x:isAlive() and not x:isTurret() end)
		caster = others[1] or target
	end
	server:castSpell(battle, caster, sp, { target }, 0)
end

--- statuses: list of status names (h6Dazed etc.), cast one by one
function Lib.statuses(server, battle, target, list, caster)
	for _, n in ipairs(list or {}) do Lib.status(server, battle, target, n, caster) end
end

--- Round 316t: lightning beam assembly of the H6 effect pack (sections 4 and 5 of the h6-vfx handoff notes, beamRoute.lua copied as is), used by the Sky Father
-- ===== h6vfx beam route (identical block in h6vfxBeamDamage.lua and h6vfxBeamAttack.lua; keep both byte-identical) =====
-- A bolt between two hexes is drawn as a chain of pre-rendered H6 pieces, each one played on the hex where it starts.
-- One-hex pieces: E W NE NW SE SW. Two-hex pieces: EE WW ENE WNW ESE WSW NNE NNW SSE SSW N S.
-- VCMI places a battle animation with its image centre on the top edge of the hex, and every piece was rendered so
-- that its start sits 40 px above that hex's centre and its end 40 px above the centre of the hex it reaches.
local BEAM_STEPS = {
	{ "E",   { "copyToEast" },                          44,   0 },
	{ "W",   { "copyToWest" },                         -44,   0 },
	{ "NE",  { "copyToNorthEast" },                     22, -42 },
	{ "NW",  { "copyToNorthWest" },                    -22, -42 },
	{ "SE",  { "copyToSouthEast" },                     22,  42 },
	{ "SW",  { "copyToSouthWest" },                    -22,  42 },
	{ "EE",  { "copyToEast", "copyToEast" },            88,   0 },
	{ "WW",  { "copyToWest", "copyToWest" },           -88,   0 },
	{ "ENE", { "copyToEast", "copyToNorthEast" },       66, -42 },
	{ "WNW", { "copyToWest", "copyToNorthWest" },      -66, -42 },
	{ "ESE", { "copyToEast", "copyToSouthEast" },       66,  42 },
	{ "WSW", { "copyToWest", "copyToSouthWest" },      -66,  42 },
	{ "NNE", { "copyToNorthEast", "copyToNorthEast" },  44, -84 },
	{ "NNW", { "copyToNorthWest", "copyToNorthWest" }, -44, -84 },
	{ "SSE", { "copyToSouthEast", "copyToSouthEast" },  44,  84 },
	{ "SSW", { "copyToSouthWest", "copyToSouthWest" }, -44,  84 },
	{ "N",   { "copyToNorthEast", "copyToNorthWest" },   0, -84 },
	{ "S",   { "copyToSouthEast", "copyToSouthWest" },   0,  84 },
}

--- Screen position of a hex centre (BattleHex: 17 x 11 grid, even rows shifted half a hex to the right).
local function beamHexPixel(hex)
	local x, y = hex:getX(), hex:getY()
	return 14 + 44 * x + ((y % 2 == 0) and 22 or 0) + 22, 86 + 42 * y + 26
end

local function beamSameHex(a, b)
	return a:getX() == b:getX() and a:getY() == b:getY()
end

--- Pieces from hex `from` to hex `to`: list of { hex = <start hex>, dir = <piece direction> }.
--- Greedy: every step takes the one- or two-hex piece whose end lands closest to `to`; two-hex pieces win ties.
local function beamRoute(from, to)
	local tx, ty = beamHexPixel(to)
	local route, cur = {}, from
	for _ = 1, 40 do
		if beamSameHex(cur, to) then break end
		local cx, cy = beamHexPixel(cur)
		local best, bestScore, bestHex = nil, nil, nil
		for _, step in ipairs(BEAM_STEPS) do
			local nx, ny = cx + step[3], cy + step[4]
			local score = (nx - tx) ^ 2 + (ny - ty) ^ 2 + (#step[2] == 1 and 30 or 0)
			if bestScore == nil or score < bestScore then
				local h = cur
				for _, m in ipairs(step[2]) do h = h[m](h) end
				if h:isValid() then best, bestScore, bestHex = step, score, h end
			end
		end
		if not best then break end
		table.insert(route, { hex = cur, dir = best[1] })
		cur = bestHex
	end
	return route
end

--- Queues one hop of the bolt (deferred: it plays together with the next change the script makes).
--- One showBattleAnimation per piece name; consecutive pieces alternate variant 0 / 1.
local function beamPlay(server, battle, prefix, from, to)
	local groups, order = {}, {}
	for i, step in ipairs(beamRoute(from, to)) do
		local name = prefix .. "_" .. step.dir .. ((i - 1) % 2)
		if not groups[name] then groups[name] = {}; table.insert(order, name) end
		table.insert(groups[name], { hex = step.hex })
	end
	for _, name in ipairs(order) do
		server:showBattleAnimation(battle, groups[name], name, "", 1, true)
	end
end

--- Hex (x, y) as a BattleHex object, reached from any hex `ref` with the neighbour functions.
local function beamHexAt(ref, x, y)
	local h = ref
	while h:getY() > y do h = (h:getX() < x) and h:copyToNorthEast() or h:copyToNorthWest() end
	while h:getY() < y do h = (h:getX() < x) and h:copyToSouthEast() or h:copyToSouthWest() end
	while h:getX() < x do h = h:copyToEast() end
	while h:getX() > x do h = h:copyToWest() end
	return h
end

--- Start hex of the first hop when a hero casts: column 0 (attacker, left) or 16 (defender, right), middle row 5.
local function beamHeroHex(ref, side)
	return beamHexAt(ref, (side == ENUM.BattleSide.defender) and 16 or 0, 5)
end
-- ===== end of h6vfx beam route =====

Lib.beamPlay = beamPlay
Lib.beamHeroHex = beamHeroHex

return Lib
