local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local P = require("lib/kadAiProxy")
--- Parameter per (for the normal creature version): when the caster is not a warfare unit, value = per x casting stack size (Touch of Darkness uses per directly).
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Touch of Darkness (Namtaru, round 428): a friendly stack (not a war machine)
---   1. dispels negative Light spell effects on it (spell source, negative, school *lightSchool);
---   2. for the next 3 rounds, enemies hit by its attacks take extra Dark damage of "X per creature x count" (W.SKILL.darkTouch, 2 at level 5).
--- Settled in combat/h7WarfareDarkTouch. AI simulation: target Attack +2 (proxy value).

local function ok(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

local function lightNegative(spellId)
	local okS, sp = pcall(function() return LIBRARY:getSpellByName(spellId) end)
	if not okS or sp == nil or not sp:isNegative() then return false end
	local okL, schools = pcall(function() return sp:getSchools() end)
	if not okL or schools == nil then return false end
	for _, s in ipairs(schools) do
		local k = (type(s) == "string") and s or (s.getJsonKey and s:getJsonKey()) or tostring(s)
		if k:sub(-11) == "lightSchool" then return true end
	end
	return false
end

local function dispelLight(server, battle, u)
	local list = u:getBonuses({ sourceType = ENUM.BonusSource.spellEffect })
	local drop = list:filter(function(b) return lightNegative(tostring(b:getSourceID())) end)
	if drop:size() > 0 then server:removeUnitBonuses(battle, u, drop) end
end

function Script:isValidTarget(mechanics, unit)
	return ok(unit)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local lv = caster and W.levelOf(caster)
	local v
	if lv == nil and self.per and caster then
		-- Normal creature version (round 428): per x casting stack size per creature (Touch of Darkness counts per creature of the target; per is the extra damage per creature per hit)
		v = self.per * (1)
	else
		lv = lv or 2
		v = W.SKILL.darkTouch[lv] or W.SKILL.darkTouch[2]
	end
	for _, dest in ipairs(target) do
		local u = dest.unit
		if ok(u) then
			if P.trial(server) then
				P.buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "attack", val = 2,
					duration = ENUM.BonusDuration.nTurns, turns = 3, valueType = ENUM.BonusValueType.additiveValue })
			else
				dispelLight(server, battle, u)
				W.setEffect(server, battle, u, "h7WarfareDarkTouch", v, 3, "h7/abilities/h7wfDarkTouch")
				server:showBattleAnimation(battle, { { unit = u } }, "h7/fx/h7wfDarkTouch", "", 1.0, true)
				server:refreshBattleUnits(battle)
			end
		end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
