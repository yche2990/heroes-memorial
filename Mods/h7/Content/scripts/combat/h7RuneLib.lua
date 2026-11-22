--- Shared by the H7 memorial runes (batch R: Rune of Fortune, Rune of Destruction, Rune of Resilience). Only loaded with require("heroes-memorial.h7:combat/h7RuneLib"), not registered as a script.
---
--- Rune Stones: summons called by spells (creatures h7RuneStoneFortune / h7RuneStoneDestruction / h7RuneStoneResilience),
---   invincible (INVINCIBLE: cannot be attacked, unaffected by spells), immobile and non-attacking like a war machine (SIEGE_WEAPON), not counted for victory (summons).
---   Stones have their own actions: they can cast Activate (once per stone per battle) and Rune of Radiance (Expert Runelore, once per stone per battle); when used up they get NOT_ACTIVE and no longer get turns.
--- Hidden marks H7_RUNE_STONE_H7C on the stone (kept apart by stacking):
---   h7RuneLevel  the hero's Rune school level 0..3 at cast time (decides aura radius and multiplier)
---   h7RuneHero   the hero's level at cast time (Activate values)
---   h7RuneUsed   Activate used
---   h7RuneRadUsed Rune of Radiance used
--- While the Rune of Radiance is active, the stone carries the visible bonus H7_RUNE_RADIANT_H7C (N rounds 2: until the end of the next round).
---
--- Aura (R.refresh): radius = 2 at Expert Runelore, otherwise 1 (counted from the stone's hex; a stack counts if one of its hexes is in range);
---   multiplier = max(1, Runelore level), x3 more with the Rune of Radiance.
---   Fortune: allies Luck +multiplier, enemies Luck -multiplier; Destruction: allies Attack +4 x multiplier; Resilience: allies Defense +6 x multiplier.
---   Several stones of the same kind on the same side take the maximum; different kinds and directions stack.
---   All stacks in the aura (friend or foe, not the Rune Stones themselves) get the hidden mark H7_RUNE_AURA_H7C, val = side of the stone + 1 (attacker 1, defender 2),
---   read by the Rune of Scattering of the Memorial Sanctum (h7RuneScattering).
---   All bonuses are kept apart by stacking "h7RuneAura..."; refresh only touches what changed.

local L = require("heroes-memorial.h7:combat/h7dLib")
local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)

local R = {}

R.STONE = "H7_RUNE_STONE_H7C"
R.RADIANT = "H7_RUNE_RADIANT_H7C"
R.AURA = "H7_RUNE_AURA_H7C"
R.LOG = "H7_RUNE_LOG_H7C"
R.PREFIX = "h7RuneAura"

R.KINDS = {
	h7RuneStoneFortune     = { kind = "fortune",     name = "Fortune", act = "h7AbRuneFortune" },
	h7RuneStoneDestruction = { kind = "destruction", name = "Destruction", act = "h7AbRuneDestruction" },
	h7RuneStoneResilience  = { kind = "resilience",  name = "Resilience", act = "h7AbRuneResilience" },
}

R.ICONS = {
	fortune     = "h7/abilities/h7RuneFortuneAura",
	misfortune  = "h7/abilities/h7RuneFortuneAura",
	destruction = "h7/abilities/h7RuneDestructionAura",
	resilience  = "h7/abilities/h7RuneResilienceAura",
	mark        = nil,
}

function R.info(u)
	if u == nil then return nil end
	local ok, key = pcall(function() return u:getCreature():getJsonKey() end)
	if not ok or key == nil then return nil end
	return R.KINDS[L.shortKey(key)]
end

function R.isStone(u)
	return u ~= nil and u:isAlive() and R.info(u) ~= nil
end

function R.stones(battle)
	return battle:getUnitsIf(function(u) return R.isStone(u) end)
end

function R.level(stone)
	return L.markVal(stone, R.STONE, "h7RuneLevel") or 0
end

function R.heroLevel(stone)
	return L.markVal(stone, R.STONE, "h7RuneHero") or 1
end

function R.used(stone, which)
	return L.markVal(stone, R.STONE, which) ~= nil
end

function R.radius(stone)
	if R.level(stone) >= 3 then return 2 end
	return 1
end

function R.isRadiant(stone)
	return stone:hasBonuses({ type = R.RADIANT })
end

function R.mult(stone)
	local m = math.max(1, R.level(stone))
	if R.isRadiant(stone) then m = m * 3 end
	return m
end

function R.inAura(stone, unit)
	return L.unitHexDistance(unit, stone:getPosition()) <= R.radius(stone)
end

--- How many usable activations remain (Activate + Expert Rune of Radiance)
function R.remaining(stone)
	local n = 0
	if not R.used(stone, "h7RuneUsed") then n = n + 1 end
	if R.level(stone) >= 3 and not R.used(stone, "h7RuneRadUsed") then n = n + 1 end
	return n
end

--- Stacks covered by the aura: alive, present, not arrow towers, not Rune Stones
local function auraTarget(u)
	return u:isAlive() and not u:isGhost() and not u:isTurret() and R.info(u) == nil
end

-- Desired bonuses: key(stacking) -> descriptor fields
local function desired(stones, unit)
	local want = {}
	local function put(key, typ, subtype, val, hidden, icon)
		local old = want[key]
		if old == nil or math.abs(val) > math.abs(old.val) then
			want[key] = { type = typ, subtype = subtype, val = val, hidden = hidden, icon = icon }
		end
	end
	local side = unit:getSide()
	for _, s in ipairs(stones) do
		if R.inAura(s, unit) then
			local tag = s:getSide() + 1
			local info = R.info(s)
			local m = R.mult(s)
			local ally = (s:getSide() == side)
			put(R.PREFIX .. "Mark" .. tag, R.AURA, nil, tag, true, nil)
			if info.kind == "fortune" then
				if ally then
					put(R.PREFIX .. "Luck" .. tag, "LUCK", nil, m, true, nil)
					put(R.PREFIX .. "LuckShow" .. tag, "H7_RUNE_FORTUNE_H7C", nil, m, false, R.ICONS.fortune)
				else
					put(R.PREFIX .. "Luck" .. tag, "LUCK", nil, -m, true, nil)
					put(R.PREFIX .. "LuckShow" .. tag, "H7_RUNE_MISFORTUNE_H7C", nil, m, false, R.ICONS.misfortune)
				end
			elseif info.kind == "destruction" and ally then
				put(R.PREFIX .. "Attack" .. tag, "PRIMARY_SKILL", "primarySkill.attack", 4 * m, true, nil)
				put(R.PREFIX .. "AttackShow" .. tag, "H7_RUNE_DESTRUCTION_H7C", nil, 4 * m, false, R.ICONS.destruction)
			elseif info.kind == "resilience" and ally then
				put(R.PREFIX .. "Defence" .. tag, "PRIMARY_SKILL", "primarySkill.defence", 6 * m, true, nil)
				put(R.PREFIX .. "DefenceShow" .. tag, "H7_RUNE_RESILIENCE_H7C", nil, 6 * m, false, R.ICONS.resilience)
			end
		end
	end
	return want
end

local function existing(unit)
	local out = {}
	local list = unit:getBonuses({ sourceType = ENUM.BonusSource.other })
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local st = b:getStacking() or ""
		if string.sub(st, 1, #R.PREFIX) == R.PREFIX then out[st] = b end
	end
	return out
end

local function byStacking(unit, key)
	return unit:getBonuses({ sourceType = ENUM.BonusSource.other }):filter(function(b) return b:getStacking() == key end)
end

--- Change a stack's aura bonuses to want; returns whether anything changed
local function sync(server, battle, unit, want)
	local changed = false
	-- First remove those that should not be there or have wrong values (removal compares type, value and source and may remove others along the way; they are added back below after reading again)
	-- Round 352: precise removal. Aura bonuses that would be removed along with it (same type, subtype and value) are removed too and re-added below from want with their icons;
	-- other scripts' bonuses with the same eight fields are restored as they were by Proxy.removeExact.
	local cur = existing(unit)
	for key, b in pairs(cur) do
		local w = want[key]
		if w == nil or w.val ~= b:getVal() then
			local keys = { [key] = true }
			for k2, b2 in pairs(cur) do
				if b2:getType() == b:getType() and b2:getVal() == b:getVal() and b2:getSubtype() == b:getSubtype() then
					keys[k2] = true
				end
			end
			local list = unit:getBonuses({ sourceType = ENUM.BonusSource.other }):filter(function(x)
				return keys[x:getStacking()] == true
			end)
			if list:size() > 0 then
				Proxy.removeExact(server, battle, unit, list)
				changed = true
			end
		end
	end
	local now = existing(unit)
	for key, w in pairs(want) do
		if now[key] == nil then
			local d = {
				type       = w.type,
				val        = w.val,
				valueType  = ENUM.BonusValueType.additiveValue,
				duration   = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.other,
				sourceID   = "heroes-memorial.h7:h7RuneStoneFortune",
				stacking   = key,
				hidden     = w.hidden
			}
			if w.subtype then d.subtype = w.subtype end
			if w.icon then d.icon = w.icon end
			server:addUnitBonus(battle, unit, d, true)
			changed = true
		end
	end
	return changed
end

--- Recalculate the rune auras of all stacks from the current situation
function R.refresh(server, battle)
	local stones = R.stones(battle)
	local units = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() end)
	local changed = false
	for _, u in ipairs(units) do
		if auraTarget(u) then
			if sync(server, battle, u, desired(stones, u)) then changed = true end
		elseif next(existing(u)) ~= nil then
			if sync(server, battle, u, {}) then changed = true end
		end
	end
	return changed
end

--- Stacks in the aura (Rune Stones excluded); pred filters further
function R.unitsInAura(battle, stone, pred)
	return battle:getUnitsIf(function(u)
		return auraTarget(u) and R.inAura(stone, u) and (pred == nil or pred(u))
	end)
end

function R.log(server, battle, index, strings, numbers)
	server:appendLog(battle, {
		append         = { "core.bonus." .. R.LOG .. ".description." .. tostring(index) },
		replaceStrings = strings or {},
		replaceNumbers = numbers or {}
	})
end

return R
