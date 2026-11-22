--- Heroes VII creatures and spells (heroes-memorial.h7): helpers shared by the Earth magic scripts (including Implosion and Time Stasis from the Prime split).
--- Not registered as a script; loaded with require("heroes-memorial.h7:combat/h7EarthLib").
---
---   Hexes: M.hexIndex(hex), M.hexDistance(a, b), M.hexTable(battle) (index -> BattleHex), M.unitHexDistance(u, hex)
---   Stacks: M.real(u) (alive, on the battlefield, not an arrow tower), M.has(u, type) (no error if the type cannot be found), M.primeImmune(u)
---   Damage: M.actor(battle, side) (any stack of that side on the field, used as the caster for Spell:adjustDamage)
---         M.spellDamage(battle, spellKey, side, unit, raw) (adjusted by the spell's school reduction, resistance and vulnerability)
---         M.spellImmune(unit, spellKey, level) (absolute immunity, immunity to the given spell, level immunity)
---   Healing: M.revive(server, battle, unit, amount) (can resurrect; with the Ring of Oblivion only the top creature is healed)
---   Marks: hidden bonus H7_EARTHMARK_H7C, kept apart by stacking name
---         M.markVal(unit, key), M.setMark(server, battle, unit, key, val, turns) (turns = nil means the whole battle), M.clearMark(...)
---         M.removeBy(server, battle, unit, type, stacking)
---   Animation: M.anim(server, battle, units, animation, sound, deferred)

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local M = {}

M.W = 17
M.MARK = "H7_EARTHMARK_H7C"

function M.hexIndex(hex)
	return hex:getX() + hex:getY() * M.W
end

function M.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function M.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[M.hexIndex(h)] = h
	end
	return t
end

function M.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do
		local d = M.hexDistance(hs:at(i), hex)
		if d < best then best = d end
	end
	return best
end

function M.has(u, t)
	local ok, r = pcall(function() return u:hasBonuses({ type = t }) end)
	return ok and r
end

--- Creatures immune to Prime (Djinn etc.; hidden mark H7_PRIME_IMMUNITY_H7C added by the creature script h7PrimeImmunity; the old name H7_PRIMEIMMUNE_H7C is also recognized).
--- Halved damage is already applied in the engine's damage flow by MORE_DAMAGE_FROM_SPELL from h7PrimeImmunity; this is only used to block negative effects.
function M.primeImmune(u)
	return M.has(u, "H7_PRIME_IMMUNITY_H7C") or M.has(u, "H7_PRIMEIMMUNE_H7C")
end

function M.real(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret()
end

function M.actor(battle, side)
	local list = battle:getUnitsIf(function(u)
		return u:getSide() == side and u:isAlive() and not u:isGhost()
	end)
	return list[1]
end

function M.spellDamage(battle, spellKey, side, unit, raw)
	raw = math.floor(raw)
	if raw <= 0 then return 0 end
	local actor = M.actor(battle, side)
	if actor == nil or spellKey == nil then return raw end
	local ok, res = pcall(function()
		local spell = LIBRARY:getSpellByName(spellKey)
		return spell:adjustDamage(battle, actor, unit, raw)
	end)
	if ok and res then return math.floor(res) end
	return raw
end

local function shortKey(key)
	local s = tostring(key or "")
	return s:match(":(.+)$") or s
end

function M.spellImmune(unit, spellKey, level)
	if spellKey ~= nil then
		local ok, imm = pcall(function()
			return unit:hasAbsoluteImmunity(LIBRARY:getSpellByName(spellKey))
		end)
		if ok and imm then return true end
		local short = shortKey(spellKey)
		local okL, list = pcall(function() return unit:getBonuses({ type = "SPELL_IMMUNITY" }) end)
		if okL and list then
			for i = 1, list:size() do
				local sub = tostring(list:getBonus(i):getSubtype() or "")
				if sub:find(short, 1, true) then return true end
			end
		end
	end
	if level and level > 0 then
		local ok, v = pcall(function() return unit:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) end)
		if ok and v and v >= level then return true end
	end
	return false
end

function M.revive(server, battle, unit, amount)
	local ok, ring = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	local level = ENUM.HealLevel.resurrect
	if ok and ring then
		level = ENUM.HealLevel.heal
		amount = math.min(amount, unit:getMaxHealth() - unit:getFirstHPleft())
	end
	if amount <= 0 then return 0, 0 end
	return server:healUnit(battle, unit, amount, level, ENUM.HealPower.permanent)
end

function M.removeBy(server, battle, unit, btype, stacking)
	local ok, list = pcall(function()
		return unit:getBonuses({ type = btype }):filter(function(b) return b:getStacking() == stacking end)
	end)
	if ok and list and list:size() > 0 then
		Proxy.removeExact(server, battle, unit, list)
	end
end

function M.markVal(unit, key)
	local ok, list = pcall(function()
		return unit:getBonuses({ type = M.MARK }):filter(function(b) return b:getStacking() == key end)
	end)
	if ok and list and list:size() > 0 then return list:getBonus(1):getVal() end
	return nil
end

function M.clearMark(server, battle, unit, key)
	M.removeBy(server, battle, unit, M.MARK, key)
end

function M.setMark(server, battle, unit, key, val, turns)
	M.clearMark(server, battle, unit, key)
	local d = {
		type       = M.MARK,
		val        = val or 1,
		sourceType = "OTHER",
		stacking   = key,
		hidden     = true,
	}
	if turns then
		d.duration = "N_TURNS"
		d.turns = turns
	else
		d.duration = "ONE_BATTLE"
	end
	server:addUnitBonus(battle, unit, d, true)
end

function M.anim(server, battle, units, animation, sound, deferred)
	local t = {}
	for _, u in ipairs(units) do t[#t + 1] = { unit = u } end
	if #t == 0 then return end
	server:showBattleAnimation(battle, t, animation, sound or "", 1.0, deferred)
end

return M
