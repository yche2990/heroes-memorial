local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local L = require("spells/h7abLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "After this attack" effects of H7 creatures (batch E), on the creature, by mode:
---   mode = "fx"       after the attack hits, play animation / sound on the stack hit (Blazing Eye on every shot; Hammer Throw only on the prepared one, mark)
---   mode = "implode"  Implosion Arrow: after the prepared (mark) shot hits, the target's hex is recorded; when this action ends (onActionFinished),
---                     stacks within radius (3) hexes of the target hex (friend or foe, excluding war machines, arrow towers and the target itself) are each pulled 1 hex toward the target (nearest first).
---                     VCMI has no facing, so H7's "turn toward the target" becomes "pulled 1 hex closer" (design list)
---   mode = "sting"    Crippling Sting: after the prepared (mark) melee attack hits, the target cannot counterattack (NO_RETALIATION) for turns rounds (this one included)
---   mode = "ink"      Ink Spray: all enemies hit by the prepared (mark) melee attack deal -pct% melee damage (counterattacks included) for turns rounds (this one included).
---                     In H7 it is "melee attacks and counterattacks miss with 50% chance"; VCMI cannot make an attack miss, so by expected value the damage is halved (design list)
--- All only count its own attacks (counterattacks and second attacks skipped); nothing happens if the carrier is dead.
--- Parameters: mode, mark, ranged (shots only), animation, sound, radius, turns, pct, show (bonus type for display), icon, log

local PENDING = "H7_IMPLODE_PENDING_H7C"

local function ownFirstAttack(payload)
	return payload ~= nil and not payload.isCounter and (payload.attackIndex or 0) == 0
end

function Script:armed(unit)
	return self.mark == nil or unit:hasBonuses({ type = self.mark })
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() or not ownFirstAttack(payload) then return end
	if self.ranged and not payload.ranged then return end
	if not self:armed(unit) then return end
	local mode = self.mode

	if mode == "fx" then
		local dests = {}
		for _, t in ipairs(payload.targets or {}) do
			if t.unit ~= nil and t.unit:isAlive() then dests[#dests + 1] = { unit = t.unit } end
		end
		if #dests > 0 and self.animation then
			server:showBattleAnimation(battle, dests, self.animation, self.sound or "", 1.0, true)
			server:refreshBattleUnits(battle)
		end

	elseif mode == "implode" then
		if not payload.ranged or other == nil then return end
		L.removeByStacking(server, battle, unit, PENDING, "h7Implode")
		L.addBonus(server, battle, unit, {
			type = PENDING, val = L.hexIndex(other:getPosition()) + 1, duration = "nTurns", turns = 1, stacking = "h7Implode", hidden = true
		})

	elseif mode == "sting" then
		if payload.ranged or other == nil or not other:isAlive() then return end
		if other:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
		self:debuff(server, battle, other, { type = "NO_RETALIATION", val = 0 })
		if self.animation then
			server:showBattleAnimation(battle, { { unit = other } }, self.animation, self.sound or "", 1.0, true)
			server:refreshBattleUnits(battle)
		end
		if self.log then L.log(server, battle, self.log, { L.name(other) }, {}) end

	elseif mode == "ink" then
		if payload.ranged then return end
		local n = 0
		for _, t in ipairs(payload.targets or {}) do
			local u = t.unit
			if u ~= nil and u:isAlive() and L.isEnemyOf(unit, u) and not u:hasBonuses({ type = "SIEGE_WEAPON" }) then
				self:debuff(server, battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = -(self.pct or 50) })
				n = n + 1
			end
		end
		if n > 0 then
			server:refreshBattleUnits(battle)
			if self.log then L.log(server, battle, self.log, { L.name(unit) }, { n }) end
		end
	end
end

--- Repeated hits of a debuff only refresh the rounds (no stacking): remove the old bonus of the same stacking group first
function Script:debuff(server, battle, u, desc)
	local stacking = "h7AbStrike_" .. self.mode
	L.removeByStacking(server, battle, u, desc.type, stacking)
	desc.duration = "nTurns"
	desc.turns = self.turns or 2
	desc.stacking = stacking
	desc.hidden = true
	L.addBonus(server, battle, u, desc)
	if self.show then
		L.removeByStacking(server, battle, u, self.show, stacking)
		L.addBonus(server, battle, u, { type = self.show, val = desc.val, duration = "nTurns", turns = self.turns or 2,
			stacking = stacking, hidden = false, icon = self.icon })
	end
end

function Script:pull(server, battle, center, exclude, shooter)
	local radius = self.radius or 3
	local list = battle:getUnitsIf(function(u)
		if not u:isAlive() or u:isGhost() or u:isTurret() then return false end
		if exclude ~= nil and u:unitID() == exclude then return false end
		if shooter ~= nil and u:unitID() == shooter then return false end -- Yu's decision (H7 audit C5): the shooter itself is not pulled
		if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
		local d = L.unitHexDistance(u, center)
		return d >= 2 and d <= radius
	end)
	table.sort(list, function(a, b) return L.unitHexDistance(a, center) < L.unitHexDistance(b, center) end)
	local moved = 0
	for _, u in ipairs(list) do
		local pos = u:getPosition()
		local now = L.unitHexDistance(u, center)
		local best, bestD = nil, now
		for _, h in ipairs(L.neighbours(pos)) do
			if L.accessible(battle, u, h) then
				local d = L.hexDistance(h, center)
				if d < bestD then best, bestD = h, d end
			end
		end
		if best ~= nil then
			local ok = pcall(function() server:moveUnit(battle, u, best, true) end)
			if ok then moved = moved + 1 end
		end
	end
	return moved
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if self.mode ~= "implode" then return end
	if other == nil or other:unitID() ~= unit:unitID() then return end
	local list = unit:getBonuses({ type = PENDING }):filter(function(b) return b:getStacking() == "h7Implode" end)
	if list:size() == 0 then return end
	local index = list:getBonus(1):getVal() - 1
	Proxy.removeExact(server, battle, unit, list)
	if not unit:isAlive() then return end
	local center = L.hexTable(battle)[index]
	if center == nil then return end
	local target = battle:getUnitByPos(center, true)
	local moved = self:pull(server, battle, center, target and target:unitID() or nil, unit:unitID())
	if self.animation then
		local dest = target and { unit = target } or { hex = center }
		server:showBattleAnimation(battle, { dest }, self.animation, self.sound or "", 1.0, true)
	end
	server:refreshBattleUnits(battle)
	if self.log then L.log(server, battle, self.log, { L.name(unit) }, { moved }) end
end

return Script
