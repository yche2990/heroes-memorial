local Base = require("spells/spellEffect")
local L = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "Uses" effect of H7 creature active abilities, written into the same spell as the ability's effects (batch E).
---
--- VCMI casts (CASTS) are shared by all active abilities of a creature, so each use is refunded here (CASTS +1, whole battle),
--- and the uses are handled by the hidden mark H7_AB_USED_H7C (stacking = key) on the casting stack:
---   uses = 1           once per battle (mark value = times used)
---   uses omitted or 0  unlimited
---   recharge = true     Hammer Throw: after one use, usable again only after a creature of the stack dies (mark value = stack size at use; restored when the count drops below it)
---   notInMelee = true   not usable with an enemy adjacent (shooting abilities: only melee when blocked)
---   shape = "2x2"       highlights the 2x2 area starting at the target hex when choosing (Diving Attack; this effect only handles the display, damage see combat/h7DivingAttackLand)
---   noRoot = true       not usable while entangled (H7_ENTANGLED_H7C) or bound (BIND_EFFECT) (Charge, Pounce, Dive)
--- Parameters: key (required), uses, recharge, notInMelee, noRoot, shape

function Script:allowed(battle, caster)
	local used = L.markVal(caster, self.key)
	if self.recharge then
		if used ~= nil and caster:getCount() >= used then return false end
	elseif (self.uses or 0) > 0 and used ~= nil and used >= self.uses then
		return false
	end
	if self.notInMelee and L.enemyAdjacent(battle, caster) then return false end
	if self.noRoot then
		-- Movement abilities cannot be used while entangled (H7_ENTANGLED_H7C, Earth Entangle / Entangling Roots) or bound (BIND_EFFECT)
		for _, t in ipairs({ "H7_ENTANGLED_H7C", "BIND_EFFECT" }) do
			local ok, has = pcall(function() return caster:hasBonuses({ type = t }) end)
			if ok and has then return false end
		end
	end
	return true
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not self:allowed(mechanics:getBattle(), caster) then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

local function square2x2(hex)
	local out = { hex }
	for _, d in ipairs({ "copyToEast", "copyToSouthWest", "copyToSouthEast" }) do
		local ok, h = pcall(function() return hex[d](hex) end)
		if ok and h ~= nil and h:isValid() then out[#out + 1] = h end
	end
	return out
end
Script.square2x2 = square2x2

function Script:adjustAffectedHexes(mechanics, hexes, spellTarget)
	if self.shape == "2x2" then
		local dest = spellTarget[1]
		if dest and dest.hex and dest.hex:isValid() then
			for _, h in ipairs(square2x2(dest.hex)) do hexes:insert(h) end
		end
	end
	return hexes
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	if self.recharge then
		L.setMark(server, battle, caster, self.key, caster:getCount())
	else
		L.setMark(server, battle, caster, self.key, (L.markVal(caster, self.key) or 0) + 1)
	end
	L.refundCast(server, battle, caster)
end

--- Round 301: newer engines call this function every time a target is chosen; returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
