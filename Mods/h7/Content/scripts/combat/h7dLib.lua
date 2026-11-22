--- Helpers shared by the batch D scripts of Heroes VII creatures and spells (heroes-memorial.h7). Only loaded with require("combat/h7dLib"), not registered as a script.
---
---   L.MOD                              this mod's name
---   L.hexIndex(hex) / L.hexDistance(a, b) / L.hexTable(battle)   hex index, distance (as the engine's BattleHex::getDistance), lookup table of all hexes
---   L.unitHexDistance(u, hex)          shortest distance from the stack's hexes to a hex
---   L.around(battle, hexes)            a set of hexes plus the ring around them (returns index -> BattleHex)
---   L.westOf(hex, k)                   k hexes west (nil off the board)
---   L.isReal(u)                        real stack: alive, not a ghost, not an arrow tower, not a war machine
---   L.otherSide(side)
---   L.spell(name)                      a spell of this mod (LIBRARY:getSpellByName, tried with and without the mod prefix)
---   L.shortKey(key)                    strip the mod prefix
---   L.obstacles(battle, spellName)     obstacles created by this spell
---   L.findMark(unit, type, stacking) / L.markVal(unit, type, stacking)
---   L.setMark(server, battle, unit, type, val, turns, stacking, hidden, extra)  removes an older mark of the same type and stacking first; turns = nil means the whole battle;
---                                      fields in extra (icon etc.) are copied into the descriptor
---   L.clearMark(server, battle, unit, type, stacking)
---   L.hasCarrier(unit, script)         whether the stack carries this combat event script (COMBAT_EVENT_TRIGGER subtype containing script)
---   L.refundCast(server, battle, unit) refund one cast (CASTS +1, whole battle): how "unlimited" creature active abilities are done
---   L.heroPower(unit)                  Spell Power of the stack's hero (0 without a hero)
---   L.name(unit)                       text id of the stack's name (singular or plural by count)
---   L.log(server, battle, index, strings, numbers)   write the battle log core.bonus.H7_LOG_D_H7C.description.<index>

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local L = {}
L.MOD = "heroes-memorial.h7"
L.W = 17
L.LOG = "H7_LOG_D_H7C"

function L.hexIndex(hex)
	return hex:getX() + hex:getY() * L.W
end

function L.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then
		return math.max(math.abs(dx), math.abs(dy))
	end
	return math.abs(dx) + math.abs(dy)
end

function L.hexTable(battle)
	local arr = battle:getAllPossibleHexes()
	local t = {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		t[L.hexIndex(h)] = h
	end
	return t
end

function L.unitHexDistance(u, hex)
	local hs = u:getHexes()
	local best = 1000
	for i = 1, hs:size() do
		local d = L.hexDistance(hs:at(i), hex)
		if d < best then best = d end
	end
	return best
end

--- hexes: Lua array (BattleHex); returns index -> BattleHex (the original hexes and the ring around them, only hexes valid on the battlefield)
function L.around(battle, hexes)
	local out = {}
	for _, h in pairs(L.hexTable(battle)) do
		for _, c in ipairs(hexes) do
			if L.hexDistance(h, c) <= 1 then
				out[L.hexIndex(h)] = h
				break
			end
		end
	end
	return out
end

function L.westOf(hex, k)
	local h = hex
	for _ = 1, k do
		if h == nil or h:getX() <= 0 then return nil end
		h = h:copyToWest()
	end
	if h ~= nil and h:isValid() then return h end
	return nil
end

function L.isReal(u)
	if u == nil or not u:isAlive() or u:isGhost() or u:isTurret() then return false end
	if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
	return true
end

function L.otherSide(side)
	if side == ENUM.BattleSide.attacker then return ENUM.BattleSide.defender end
	return ENUM.BattleSide.attacker
end

function L.shortKey(key)
	if key == nil then return "" end
	return key:match(":([^:]+)$") or key
end

function L.spell(name)
	local ok, s = pcall(function() return LIBRARY:getSpellByName(L.MOD .. ":" .. name) end)
	if ok and s ~= nil then return s end
	ok, s = pcall(function() return LIBRARY:getSpellByName(name) end)
	if ok then return s end
	return nil
end

function L.obstacles(battle, spellName)
	local out = {}
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and L.shortKey(s:getJsonKey()) == spellName then out[#out + 1] = o end
	end
	return out
end

local function marks(unit, typ, stacking)
	return unit:getBonuses({ type = typ }):filter(function(b)
		return stacking == nil or b:getStacking() == stacking
	end)
end

function L.findMark(unit, typ, stacking)
	local list = marks(unit, typ, stacking)
	if list:size() == 0 then return nil end
	return list:getBonus(1)
end

function L.markVal(unit, typ, stacking)
	local b = L.findMark(unit, typ, stacking)
	if b == nil then return nil end
	return b:getVal()
end

function L.clearMark(server, battle, unit, typ, stacking)
	local list = marks(unit, typ, stacking)
	if list:size() > 0 then Proxy.removeExact(server, battle, unit, list) end
end

function L.setMark(server, battle, unit, typ, val, turns, stacking, hidden, extra)
	L.clearMark(server, battle, unit, typ, stacking)
	local d = {
		type       = typ,
		val        = val,
		valueType  = ENUM.BonusValueType.additiveValue,
		duration   = turns and ENUM.BonusDuration.nTurns or ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		sourceID   = unit:getCreature():getJsonKey(),
		hidden     = hidden ~= false
	}
	if turns then d.turns = turns end
	if stacking then d.stacking = stacking end
	for k, v in pairs(extra or {}) do d[k] = v end
	server:addUnitBonus(battle, unit, d, true)
end

function L.hasCarrier(unit, script)
	local list = unit:getBonuses({ type = "COMBAT_EVENT_TRIGGER" })
	for i = 1, list:size() do
		local st = list:getBonus(i):getSubtype() or ""
		if string.find(st, script, 1, true) then return true end
	end
	return false
end

function L.refundCast(server, battle, unit)
	if unit == nil then return end
	server:addUnitBonus(battle, unit, {
		type       = "CASTS",
		val        = 1,
		valueType  = ENUM.BonusValueType.additiveValue,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.creatureAbility,
		sourceID   = unit:getCreature():getJsonKey(),
		hidden     = true
	}, true)
end

function L.heroPower(unit)
	local ok, v = pcall(function()
		return unit:getBonusesValue({ type = "PRIMARY_SKILL", subtype = "primarySkill.spellpower" })
	end)
	if ok and type(v) == "number" then return math.max(0, v) end
	return 0
end

function L.name(unit)
	return unit:getCreature():getNameTextID(math.max(1, unit:getCount()))
end

function L.log(server, battle, index, strings, numbers)
	server:appendLog(battle, {
		append         = { "core.bonus." .. L.LOG .. ".description." .. tostring(index) },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

return L
