--- Heroes VII creatures and spells (heroes-memorial.h7): helpers shared by the Light and Dark magic batch (SL).
--- Not registered as a script; loaded with require("heroes-memorial.h7:combat/h7SLLib").
---
---   M.has(unit, type)                      look up a bonus type (no error if the type does not exist)
---   M.schoolImmune(unit, tag)              immune to this school (school immunity, negative school immunity, school damage reduction >= 100); tag e.g. "lightSchool"
---   M.resist(unit, raw, tag, spellKey)     adjusted like the engine's spell damage (as CSpell::adjustRawDamage): first the school's damage reduction,
---                                          then the all-school reduction, then MORE_DAMAGE_FROM_SPELL (this spell); 0 when invincible
---   M.hostile(battle, a, b)                whether a and b are hostile (battle:isHostile; older engines compare sides)
---   M.real(u)                              alive, present, not an arrow tower, not a war machine
---   M.ownBonuses(unit, type, key)          bonuses of a type whose source is a spell effect with key in the source id
---   M.anim(server, battle, units, anim, sound, alpha)   deferred animation (must be followed by a change or refreshBattleUnits)
---   M.perishLog(server, battle, unit, killed)            "X creatures perish" battle log line
---
--- Method shared by sharing / absorbing (Martyrdom, Celestial Armor): "temporary reduction before the hit, worked out backwards after it" (as h47MartyrGuard, h47ShadowCloak):
---   M.preHit(server, battle, unit, tag, linkType)   before the hit: without other sharing, add a temporary pct% reduction (pct = 90 - other armor-type reductions)
---                                                   and the hidden mark linkType (value = (other reductions + 1000) x 100 + pct). Returns true if added
---   M.postHit(server, battle, unit, tag, linkType, payload, script)
---                                                   After the hit: remove the temporary reduction and the mark, return dealt (damage actually taken) and
---                                                   full (damage that would have been taken without this temporary reduction); nil if nothing was added for this hit
---   M.settle(server, battle, unit, dealt, want)     change the result of this hit to want: heal what was taken too little (can resurrect), deal what was taken too much

local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local BattleLog = require("battleLog")

local M = {}

local REDUCTION = "GENERAL_DAMAGE_REDUCTION"
local ALL = "damageTypeAll"
local SHARE = "h7Share"

function M.has(unit, t)
	local ok, r = pcall(function() return unit:hasBonuses({ type = t }) end)
	return ok and r
end

local function subtypeHas(b, tag)
	local sub = tostring(b:getSubtype() or "")
	return string.find(sub, tag, 1, true) ~= nil
end

--- H7 audit B8: summed with the engine's stacking rules (within one stacking group only the entry with the largest absolute value counts; entries without a stacking group all add up)
local function stackedSum(list, pred)
	local total, groups = 0, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		if pred(b) then
			local v = b:getVal()
			local st = b:getStacking() or ""
			if st == "" then total = total + v
			elseif groups[st] == nil or math.abs(v) > math.abs(groups[st]) then groups[st] = v end
		end
	end
	for _, v in pairs(groups) do total = total + v end
	return total
end

function M.schoolImmune(unit, tag)
	local function by(t, pred)
		local ok, list = pcall(function() return unit:getBonuses({ type = t }) end)
		if not ok or not list then return false end
		return list:filter(function(b) return subtypeHas(b, tag) and (pred == nil or pred(b)) end):size() > 0
	end
	if by("SPELL_SCHOOL_IMMUNITY") then return true end
	if by("NEGATIVE_EFFECTS_IMMUNITY") then return true end
	local total = 0
	local ok, list = pcall(function() return unit:getBonuses({ type = "SPELL_DAMAGE_REDUCTION" }) end)
	if ok and list then
		total = stackedSum(list, function(b) return subtypeHas(b, tag) end)
	end
	return total >= 100
end

function M.resist(unit, raw, tag, spellKey)
	if unit:isInvincible() then return 0 end
	local dmg = raw
	local list = unit:getBonuses({ type = "SPELL_DAMAGE_REDUCTION" })
	local function isAny(b)
		local sub = tostring(b:getSubtype() or "")
		return sub == "any" or sub == "spellSchool.any"
	end
	local any = stackedSum(list, isAny)
	local school = stackedSum(list, function(b)
		return not isAny(b) and string.find(tostring(b:getSubtype() or ""), tag, 1, true) ~= nil
	end)
	if school ~= 0 then dmg = math.floor(dmg * (100 - school) / 100) end
	if any ~= 0 then dmg = math.floor(dmg * (100 - any) / 100) end
	if spellKey then
		local more = unit:getBonuses({ type = "MORE_DAMAGE_FROM_SPELL" }):filter(function(b)
			return subtypeHas(b, spellKey)
		end)
		local add = 0
		for i = 1, more:size() do add = add + more:getBonus(i):getVal() end
		if add ~= 0 then dmg = math.floor(dmg * (100 + add) / 100) end
	end
	if dmg < 0 then dmg = 0 end
	return dmg
end

--- Whether a and b are hostile (hypnotized stacks count for their controller; older engines without isHostile compare sides)
function M.hostile(battle, a, b)
	local ok, r = pcall(function() return battle:isHostile(a, b) end)
	if ok and r ~= nil then return r end
	return a:getSide() ~= b:getSide()
end

function M.real(u)
	if not u:isAlive() or u:isGhost() then return false end
	if u:isTurret() then return false end
	if M.has(u, "SIEGE_WEAPON") then return false end
	return true
end

function M.ownBonuses(unit, t, key)
	return unit:getBonuses({ type = t, sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		return string.find(tostring(b:getSourceID() or ""), key, 1, true) ~= nil
	end)
end

function M.anim(server, battle, units, anim, sound, alpha)
	local list = {}
	for _, u in ipairs(units) do list[#list + 1] = { unit = u } end
	if #list == 0 then return end
	server:showBattleAnimation(battle, list, anim, sound or "", alpha or 0.85, true)
end

function M.perishLog(server, battle, unit, killed)
	if killed and killed > 0 then BattleLog.creaturesPerish(server, battle, unit, killed) end
end

-- ---------------------------------------------------------------- Sharing / absorbing

local function isShare(b)
	local s = b:getStacking()
	-- H7 audit A2: the Rune of Balance (h7RuneZone) uses the stacking group "h7RuneShare", which was not recognized, so it was taken for armor and another reduction was added, making damage vanish
	return string.sub(s, 1, #SHARE) == SHARE or string.sub(s, 1, 8) == "h47Share" or s == "h7RuneShare"
end

local function shareReductions(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(isShare)
end

--- Total of the "armor-type" reductions in the damage calculation (spell sources and temporary sharing reductions excluded)
local function otherReduction(unit)
	return unit:getBonuses({ type = REDUCTION, subtype = ALL }):filter(function(b)
		return b:getSource() ~= ENUM.BonusSource.spellEffect and not isShare(b)
	end):totalValue()
end

local function links(unit, linkType, tag)
	return unit:getBonuses({ type = linkType }):filter(function(b) return b:getStacking() == SHARE .. tag end)
end

function M.preHit(server, battle, unit, tag, linkType)
	-- Clear what was left from last time first
	local old = links(unit, linkType, tag)
	if old:size() > 0 then
		Proxy.removeExact(server, battle, unit, old)
		local mine = shareReductions(unit):filter(function(b) return b:getStacking() == SHARE .. tag end)
		if mine:size() > 0 then Proxy.removeExact(server, battle, unit, mine) end
	end
	if not unit:isAlive() then return false end
	local rest = otherReduction(unit)
	local pct = 0
	-- This hit is already shared by something else (Martyrdom, Rune of Balance, another Martyrdom or Celestial Armor): no reduction, heal by the actual damage after the hit
	if shareReductions(unit):size() == 0 then
		pct = math.max(0, math.min(90, 90 - rest))
	end
	if rest >= 100 then return false end
	local source = unit:getCreature():getJsonKey()
	if pct > 0 then
		server:addUnitBonus(battle, unit, {
			type = REDUCTION, subtype = ALL, val = pct,
			duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = source,
			stacking = SHARE .. tag, hidden = true
		}, true)
	end
	server:addUnitBonus(battle, unit, {
		type = linkType, val = (rest + 1000) * 100 + pct,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = source,
		stacking = SHARE .. tag, hidden = true
	}, true)
	return true
end

function M.postHit(server, battle, unit, tag, linkType, payload, script)
	local l = links(unit, linkType, tag)
	if l:size() == 0 then return nil end
	local v = l:getBonus(1):getVal()
	Proxy.removeExact(server, battle, unit, l)
	local mine = unit:getBonuses({ type = REDUCTION, subtype = ALL, sourceType = ENUM.BonusSource.other }):filter(function(b)
		return b:getStacking() == SHARE .. tag
	end)
	if mine:size() > 0 then Proxy.removeExact(server, battle, unit, mine) end
	local pct = v % 100
	local rest = math.floor(v / 100) - 1000
	local entry = script:ownEntry(unit, payload)
	local dealt = entry and entry.damage or 0
	local full = dealt
	local denom = 100 - rest - pct
	if pct > 0 and denom > 0 then
		full = math.floor(dealt * (100 - rest) / denom + 0.5)
	end
	return dealt, full
end

function M.settle(server, battle, unit, dealt, want)
	if want < dealt then
		if unit:isAlive() then
			server:healUnit(battle, unit, dealt - want, ENUM.HealLevel.resurrect, ENUM.HealPower.permanent)
		end
	elseif want > dealt then
		if unit:isAlive() then
			local _, killed = server:damageUnit(battle, unit, want - dealt)
			M.perishLog(server, battle, unit, killed)
		end
	end
end

return M
