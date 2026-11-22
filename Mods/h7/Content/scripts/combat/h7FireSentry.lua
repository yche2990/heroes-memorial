local Base = require("combat/combatScript")
local L = require("combat/h7SfLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shots of the Fire Sentry (H7) (when spells/h7FireSentry summons a sentry it is added as a battle-wide combat event with addBattleBonus, triggered by every stack;
--- the script recognizes sentries by the hidden mark H7_FIRESENTRY_H7C):
---   onRoundStart: H7 "at the end of each round" = VCMI the start of the next round. Each sentry shoots the two nearest enemies once each for Fire damage
---                 (damage = the mark's value, after Fire immunity, Fire damage reduction and the casting hero's Fire bonus), then its shots -1; when used up the sentry is removed.
---   onAfterAttack: after an enemy's first ranged attack each round (not counterattacks or second shots), every sentry of the other side shoots back at that shooter once
---                 (each sentry once per round: mark H7_FIRESENTRY_FIRED_H7C until the end of the round).

local DMG, LIFE, FIRED = "H7_FIRESENTRY_H7C", "H7_FIRESENTRY_LIFE_H7C", "H7_FIRESENTRY_FIRED_H7C"
local SPELL = "heroes-memorial.h7:h7FireSentry"

local function isSentry(u)
	return u:isAlive() and not u:isGhost() and u:hasBonuses({ type = DMG })
end

local function shoot(server, battle, sentry, target)
	if target == nil or not target:isAlive() or target:isGhost() then return end
	if L.fireImmune(target, SPELL) then return end
	local raw = sentry:getBonusesValue({ type = DMG })
	local dmg = raw
	local spell = LIBRARY:getSpellByName(SPELL)
	if spell then
		local ok, adj = pcall(function() return spell:adjustDamage(battle, sentry, target, raw) end)
		if ok and type(adj) == "number" then dmg = adj else dmg = L.fireDamage(target, raw) end
	else
		dmg = L.fireDamage(target, raw)
	end
	if dmg <= 0 then return end
	server:showBattleAnimation(battle, { { unit = target } }, "h7/fx/sfSentryShot", "h7/sf_fire_sentry_shoot.ogg", 1.0, true)
	server:damageUnit(battle, target, dmg)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not isSentry(unit) then return end
	local side = unit:getSide()
	local foes = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:isInvincible()
	end)
	-- The two nearest; random among equal distances
	local keyed = {}
	for _, u in ipairs(foes) do keyed[#keyed + 1] = { u = u, d = L.unitDistance(unit, u), r = server:rngInt(0, 999) } end
	table.sort(keyed, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.r < b.r end)
	for i = 1, math.min(2, #keyed) do shoot(server, battle, unit, keyed[i].u) end

	local left = unit:getBonusesValue({ type = LIFE }) - 1
	if left > 0 then
		L.setMark(server, battle, unit, LIFE, left)
	else
		-- The animation before leaving cannot be deferred (animation rules, checklist section 10)
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/sfBurning", "", 1.0, false)
		server:removeUnit(battle, unit)
		server:refreshBattleUnits(battle)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload or not payload.ranged or payload.isCounter then return end
	if (payload.attackIndex or 0) > 0 then return end
	if not unit:isAlive() or unit:isGhost() or isSentry(unit) then return end
	local side = unit:getSide()
	local sentries = battle:getUnitsIf(function(u)
		return u:getSide() ~= side and isSentry(u) and not u:hasBonuses({ type = FIRED })
	end)
	for _, s in ipairs(sentries) do
		if unit:isAlive() then
			L.setMark(server, battle, s, FIRED, 1, 1)
			shoot(server, battle, s, unit)
		end
	end
end

return Script
