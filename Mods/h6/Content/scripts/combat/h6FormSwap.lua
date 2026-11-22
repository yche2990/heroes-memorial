--- Shared helpers for "changing form" (round 360: the Sun Steed SunStallion switches to the light-form model; round 360b: Dual Form uses the same method).
--- Only loaded with require("combat/h6FormSwap"), not registered as a script.
---
--- How it works: the original stack O is not removed but "hidden" (ghost flag, which the engine treats as having left: not in the turn order, occupies no hex,
--- cannot be targeted, but keeps its count, experience, artifacts and army slot); a temporary light-form stack G (summoned,
--- does not join the army after battle) is added in its place. Changes to G (damage, death, resurrection) are synced back to O at once; when changing back, G is removed, O is put back on G's hex,
--- and the spell effects and temporary battle bonuses G gained / lost during the round are moved back to O. Therefore:
---   * Spells on it (Haste, Bless, Slow, Curse...), ability marks and cooldowns go along, and remaining rounds continue when changing back;
---   * bonuses from creature experience, hero specialty and stack artifacts are copied to G (source recorded as creature experience, whole battle, only active in light form); O itself is untouched;
---   * if the battle ends in light form (retreat and surrender included), it is settled as O: count as G currently has, experience as usual, no extra light-form stack.
--- When the original stack is hidden it is flagged "morale already triggered this round", so the engine does not roll high morale for the hidden stack after the cast and let it act again.

local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local M = {}

M.LINK = "h6SunSteedOrig"   -- Mark on the temporary-form stack: id of the original stack (shared by Sun Steed and Dual Form)

local function durMask(b)
	local d = 0
	for _, x in ipairs(b:getDuration() or {}) do d = d + x end
	return d
end

-- Subtype: the name read can be written back as is; the number -1 means "no subtype" (as kadAiProxy.restoreSubtype)
local DAMAGE_SUB = { ["0"] = "damageTypeMelee", ["1"] = "damageTypeRanged" }
local DAMAGE_TYPES = { GENERAL_DAMAGE_REDUCTION = true, PERCENTAGE_DAMAGE_BOOST = true, FIRST_STRIKE = true }
local function subtypeOf(b)
	local sub = b:getSubtype()
	if sub == nil or sub == "" or sub == "none" or sub == "-1" then return nil end
	local n = tonumber(sub)
	if n == nil then return sub end
	if DAMAGE_TYPES[b:getType()] and DAMAGE_SUB[sub] then return DAMAGE_SUB[sub] end
	return n
end

local function key(b)
	return table.concat({ b:getType(), b:getSubtype(), tostring(b:getSource()), b:getSourceID(), b:getVal(),
		tostring(b:getValType()), tostring(b:getEffectRange()), durMask(b), b:getStacking(), b:getTurnsRemain(),
		tostring(b:isHidden()) }, "|")
end

-- Description written back as is; asCopy = copy for the light-form stack only (source recorded as creature experience, whole battle)
local function descOf(b, asCopy)
	local d = {
		type = b:getType(), val = b:getVal(), valueType = b:getValType(), effectRange = b:getEffectRange(),
		duration = durMask(b), stacking = b:getStacking(), hidden = b:isHidden()
	}
	local sub = subtypeOf(b)
	if sub ~= nil then d.subtype = sub end
	if b:getTurnsRemain() > 0 then d.turns = b:getTurnsRemain() end
	-- Round 419: both reads throw when addInfo is a JSON object (parameters of combat event scripts), so they are wrapped
	local okv, vec = pcall(function() return b:getParametersAsVector() end)
	if okv and vec ~= nil and #vec > 0 then d.addInfo = vec
	else
		local okn, n = pcall(function() return b:getParametersAsNumber() end)
		if okn and n ~= nil and n ~= 0 then d.addInfo = n end
	end
	local src = b:getSource()
	if asCopy then
		-- Source recorded as "creature experience": stacking unchanged (the experience charge bonus must replace the creature's own, not stack); not treated as a movable bonus when changing back
		d.sourceType = ENUM.BonusSource.stackExperience
		d.duration = ENUM.BonusDuration.oneBattle; d.turns = nil
	elseif src == ENUM.BonusSource.spellEffect and L.spell(b:getSourceID()) ~= nil then
		d.sourceType = src; d.sourceID = b:getSourceID()
	elseif src == ENUM.BonusSource.creatureAbility and b:getSourceID() ~= "" then
		d.sourceType = src; d.sourceID = b:getSourceID()
	else
		d.sourceType = ENUM.BonusSource.other
	end
	return d
end

local function isOwnAbility(b)
	return b:getSource() == ENUM.BonusSource.creatureAbility and durMask(b) == ENUM.BonusDuration.permanent
end

-- Creature abilities are not compared by source id (the original and light-form creatures are two creatures): not copied if the light-form creature already has the same one
local function abilityKey(b)
	return table.concat({ b:getType(), b:getSubtype(), b:getVal(), tostring(b:getValType()), tostring(b:getEffectRange()),
		b:getStacking() }, "|")
end

-- Abilities of the original creature related to the Sun Steed itself that the light form must not have (casting this ability, casts, cooldown trigger)
local NOT_FOR_LIGHT = { SPELLCASTER = true, CASTS = true, NO_SPELLCAST_BY_DEFAULT = true }
local function steedOnly(b)
	if NOT_FOR_LIGHT[b:getType()] then return true end
	-- Round 419: COMBAT_EVENT_TRIGGER is not in the engine's bonus type table, so getType() returns an empty string; the subtype carries the mod prefix
	local t, sub = b:getType(), tostring(b:getSubtype() or "")
	return (t == "" or t == "COMBAT_EVENT_TRIGGER") and (sub == "h6Cooldown" or sub:sub(-12) == ":h6Cooldown")
end

--- Round 419: bonuses whose type cannot be read (COMBAT_EVENT_TRIGGER etc.) cannot be rebuilt as they are, so they are not moved
local function rebuildable(b) return (b:getType() or "") ~= "" end

--- Bonuses that change during battle and must be moved both ways: spell effects, and temporary bonuses with source "other / creature ability" added by scripts (ability marks, cooldowns...)
local function transferable(b)
	local src = b:getSource()
	if src ~= ENUM.BonusSource.spellEffect and src ~= ENUM.BonusSource.other and src ~= ENUM.BonusSource.creatureAbility then return false end
	if durMask(b) == ENUM.BonusDuration.permanent then return false end
	if (b:getStacking() or "") == M.LINK then return false end
	-- Casts are counted separately: refund bonuses stay on their own stacks (copying them would give the temporary stack extra casts)
	if b:getType() == "CASTS" then return false end
	return true
end

local function count(list, pred)
	local c, sample = {}, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if pred(b) then
			local k = key(b); c[k] = (c[k] or 0) + 1; sample[k] = b
		end
	end
	return c, sample
end

--- Not slowed in light form (original "immune to movement reduction"): negative speed from spells is not copied
local function slowing(b)
	return b:getSource() == ENUM.BonusSource.spellEffect and b:getType() == "STACKS_SPEED" and b:getVal() < 0
end

--- Bonuses to add when going from original stack O to light-form stack G: those O has and G does not. Of O's own creature abilities only those the light-form creature lacks
--- (abilities other mods add per creature go along too); the Sun Steed's own casting ability is not added
--- opts.abilities = false: do not copy the original creature's own abilities (Dual Form: the two forms have different abilities anyway)
--- opts.keepSlow = true: also copy slowing from spells (only the Sun Steed's light form is immune to slowing)
function M.snapshotFor(O, opts)
	opts = opts or {}
	local all = O:getBonuses({})
	local out = {}
	for i = 1, all:size() do
		local b = all:getBonus(i)
		local skip = (slowing(b) and not opts.keepSlow) or (isOwnAbility(b) and (steedOnly(b) or opts.abilities == false))
			or b:getType() == "CASTS" or not rebuildable(b)
		if not skip then
			out[#out + 1] = { k = key(b), ak = isOwnAbility(b) and abilityKey(b) or nil, d = descOf(b, not transferable(b)) }
		end
	end
	return out
end

function M.copyTo(server, battle, G, snapshot)
	local gl = G:getBonuses({})
	local have = count(gl, function() return true end)
	local haveAb = {}
	for i = 1, gl:size() do
		local b = gl:getBonus(i)
		if isOwnAbility(b) then local k = abilityKey(b); haveAb[k] = (haveAb[k] or 0) + 1 end
	end
	local used, usedAb = {}, {}
	for _, e in ipairs(snapshot) do
		local k, pool, u = e.k, have, used
		if e.ak ~= nil then k, pool, u = e.ak, haveAb, usedAb end
		u[k] = (u[k] or 0) + 1
		if u[k] > (pool[k] or 0) then server:addUnitBonus(battle, G, e.d, true) end
	end
end

--- Changing back: sync G's movable bonuses to O (add what G has more of, remove what O has more of; cooldown marks are only added, never removed, since cooldowns added after O was hidden must stay)
function M.syncBack(server, battle, G, O)
	local function movable(b) return transferable(b) and rebuildable(b) end
	local cg, sg = count(G:getBonuses({}), movable)
	local co, so = count(O:getBonuses({}), movable)
	-- What O has more of than G: remove all of that entry from O, then add back as many as G has (the engine matches eight fields when removing, so a single entry cannot be removed)
	local drop = {}
	for k, n in pairs(co) do
		if n > (cg[k] or 0) and so[k]:getType() ~= "H6_COOLDOWN_H6C" then drop[k] = true end
	end
	if next(drop) ~= nil then
		local list = O:getBonuses({}):filter(function(b) return movable(b) and drop[key(b)] == true end)
		if list:size() > 0 then Proxy.removeExact(server, battle, O, list) end
	end
	-- What G has more of than O (including those just removed): add up to G's count
	for k, n in pairs(cg) do
		local have = drop[k] and 0 or (co[k] or 0)
		for _ = have + 1, n do server:addUnitBonus(battle, O, descOf(sg[k], false), true) end
	end
end

--- Temporary form T back to the original stack O: move bonuses back, remove T, put O on T's hex (health as T)
function M.swapBack(server, battle, T, O)
	local pos = T:getPosition()
	local health = T:isAlive() and T:getAvailableHealth() or 0
	M.syncBack(server, battle, T, O)
	server:removeUnit(battle, T)
	M.restore(server, battle, O, pos, health)
	return pos, health
end

--- Original stack O into temporary form to: hide O, add to (temporary stack) in place, copy bonuses, align health, record the original stack id. Returns the new stack
function M.swapOut(server, battle, O, to, opts)
	local hex = O:getPosition()
	local health = O:getAvailableHealth()
	local carry = M.snapshotFor(O, opts)
	M.hide(server, battle, O)
	local G = server:addUnit(battle, { count = O:getCount(), type = to, side = O:getSide(), position = hex, summoned = true })
	if G == nil then
		M.restore(server, battle, O, hex, health)
		return nil
	end
	M.copyTo(server, battle, G, carry)
	local cur = G:getAvailableHealth()
	if cur > health then
		local st = G:copy(); st:damage(cur - health); server:changeUnit(battle, st, 0)
	end
	L.setMark(server, battle, G, M.LINK, O:unitID())
	return G
end

function M.byId(battle, id)
	local list = battle:getUnitsIf(function(u) return u:unitID() == id end)
	return list[1]
end

function M.original(battle, G)
	local id = L.markValue(G, M.LINK)
	if id == nil then return nil end
	return M.byId(battle, id)
end

--- O's health follows G's current state (O is hidden: no animation, no death event)
function M.syncHealth(server, battle, G, O)
	if O == nil then return end
	local gh = G:isAlive() and G:getAvailableHealth() or 0
	local oh = O:isAlive() and O:getAvailableHealth() or 0
	if gh == oh then return end
	local st = O:copy()
	if gh < oh then
		st:damage(oh - gh); server:changeUnit(battle, st, gh - oh)
	elseif O:isAlive() then
		st:heal(gh - oh, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent); server:changeUnit(battle, st, gh - oh)
	end
end

--- Hide the original stack
function M.hide(server, battle, O)
	local st = O:copy()
	st:setGhost(true)
	st:setHadMorale(true)
	server:changeUnit(battle, st, 0)
end

--- Put the original stack back: position and health as G (G must be removed first to free the hex)
function M.restore(server, battle, O, pos, health)
	local st = O:copy()
	st:setGhost(false)
	st:setPosition(pos)
	server:changeUnit(battle, st, 0)
	local cur = O:isAlive() and O:getAvailableHealth() or 0
	if health > cur then
		st = O:copy(); st:heal(health - cur, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent); server:changeUnit(battle, st, health - cur)
	elseif health < cur then
		st = O:copy(); st:damage(cur - health); server:changeUnit(battle, st, health - cur)
	end
end

return M
