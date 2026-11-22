local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local P = require("lib/kadAiProxy")
--- Parameter per (for the normal creature version): when the caster is not a warfare unit, value = per x casting stack size (Touch of Darkness uses per directly).
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cloak of Death (Faceless, round 428): cloaks a friendly stack (not a war machine) until the end of this round;
--- the next enemy to attack it in melee first takes X Dark damage (W.SKILL.cloak). Level 5: if the cloak is still there at the end of the round, it explodes against surrounding enemies (W.SKILL.cloakBurst).
--- Settled in combat/h7WarfareCloak. AI simulation: target Defense +5 this round (proxy value).

local function ok(u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and not u:hasBonuses({ type = "SIEGE_WEAPON" })
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
		v = self.per * (caster:getCount())
	else
		lv = lv or 2
		v = W.SKILL.cloak[lv] or W.SKILL.cloak[2]
	end
	for _, dest in ipairs(target) do
		local u = dest.unit
		if ok(u) then
			if P.trial(server) then
				P.buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "defence", val = 5,
					duration = ENUM.BonusDuration.nTurns, turns = 1, valueType = ENUM.BonusValueType.additiveValue })
			else
				W.setEffect(server, battle, u, "h7WarfareCloak", v, nil, "h7/abilities/h7wfDeathCloak")
				if lv ~= nil and lv >= 5 then W.setMark(server, battle, u, "h7Wf:h7WarfareCloak|burst", W.SKILL.cloakBurst)
				else W.clearMark(server, battle, u, "h7Wf:h7WarfareCloak|burst") end
				server:showBattleAnimation(battle, { { unit = u } }, "h7/fx/h7wfCloak", "", 1.0, true)
				server:refreshBattleUnits(battle)
			end
		end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
