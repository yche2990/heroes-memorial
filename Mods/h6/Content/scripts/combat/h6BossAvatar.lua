local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Passives of the Void Avatar (H6 boss):
---   Erase: a normal attack knocks the struck single-hex stack back 1 hex (when this action ends);
---   Void Oppression: at the start of each round, adjacent enemies are Dazed (H6 Dazed) and deal -aura% damage this round;
---   Curse of Oblivion: the first attacker each round deals no damage (restored at once); a melee attacker is pushed back 2 hexes when this action ends;
---   Reflection: after that, reflect% of the damage it takes is passed to a random adjacent enemy;
---   Void Gate: enemies carrying its gate (H6_VOIDGATE_H6C) lose gate% of their count at the start of each round;
---   Void Circle (while H6_VOIDCIRCLE_H6C is active): regains heal% of its health at battle start each round, enemies within 2 hexes take circle damage, and enemies beyond 2 hexes deal -90% damage to it.
--- Parameters: aura, daze, reflect, gate, heal, circle, animation, sound

-- Knockback does not move the unit in the middle of attack resolution (a pushed unit would still be retaliated against from a distance); remember it and push when this action ends; each stack is pushed at most once per action (the longest distance)
local pendingKnock = {}
local function queueKnock(unit, target, dist)
	local id = unit:unitID()
	pendingKnock[id] = pendingKnock[id] or {}
	for _, e in ipairs(pendingKnock[id]) do
		if e.id == target:unitID() then
			if dist > e.dist then e.dist = dist end
			return
		end
	end
	table.insert(pendingKnock[id], { id = target:unitID(), dist = dist })
end

local function hostileNear(battle, unit, dist)
	return battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(unit, u) and L.unitDistance(unit, u) <= dist end)
end

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	local src = unit:getCreature():getJsonKey()
	local near = hostileNear(battle, unit, 1)
	local daze = self.daze and L.spell(self.daze)
	for _, u in ipairs(near) do
		L.removeByStacking(server, battle, u, "GENERAL_DAMAGE_PREMY", "h6VoidAura")
		server:addUnitBonus(battle, u, { type = "GENERAL_DAMAGE_PREMY", val = -(self.aura or 60), duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h6VoidAura" }, true)
		if daze then server:applySpellEffects(battle, unit, daze, { u }, 3, 1, false) end
	end
	-- Void Gate
	local id = unit:unitID() + 1
	for _, u in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getBonuses({ type = "H6_VOIDGATE_H6C" }):filter(function(b) return b:getVal() == id end):size() > 0 end)) do
		local n = math.max(1, math.ceil(u:getCount() * (self.gate or 3) / 100))
		local amount = (n - 1) * u:getMaxHealth() + u:getFirstHPleft()
		local dealt, killed = L.rawHit(server, battle, u, amount, self.animation, self.sound)
		L.log(server, battle, "H6_VOIDGATE_H6C", 1, { L.name(u) }, { killed or 0 })
	end
	-- Void Circle
	if unit:hasBonuses({ type = "H6_VOIDCIRCLE_H6C" }) then
		server:healUnit(battle, unit, math.floor(L.initialHealth(unit) * (self.heal or 8) / 100), ENUM.HealLevel.heal, ENUM.HealPower.permanent)
		for _, u in ipairs(hostileNear(battle, unit, 2)) do L.hit(server, battle, u, self.circle or 100, self.animation, self.sound) end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if other == nil or not unit:hasBonuses({ type = "H6_VOIDCIRCLE_H6C" }) or not battle:isHostile(unit, other) then return end
	if L.unitDistance(unit, other) > 2 then
		server:addUnitBonus(battle, other, { type = "GENERAL_DAMAGE_PREMY", val = -90, duration = ENUM.BonusDuration.nTurns, turns = 1,
			sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = "h6VoidCircleOut" }, true)
	end
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if other ~= nil then L.removeByStacking(server, battle, other, "GENERAL_DAMAGE_PREMY", "h6VoidCircleOut") end
	if not unit:isAlive() or other == nil or not battle:isHostile(unit, other) then return end
	local e = self:ownEntry(unit, payload)
	local dmg = e and e.damage or 0
	if not L.markValue(unit, "h6Oblivion") then
		L.setMark(server, battle, unit, "h6Oblivion", 1, 1)
		if dmg > 0 then server:healUnit(battle, unit, dmg, ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
		if other:isAlive() and L.adjacent(unit, other) and server:describeChanges() then queueKnock(unit, other, 2) end
		L.log(server, battle, "H6_OBLIVION_H6C", 1, { L.name(other) }, {})
		if server:describeChanges() then server:refreshBattleUnits(battle) end
		return
	end
	local share = math.floor(dmg * (self.reflect or 10) / 100)
	local near = hostileNear(battle, unit, 1)
	if share > 0 and #near > 0 then L.hit(server, battle, near[server:rngInt(1, #near)], share, self.animation, self.sound) end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	for _, t in ipairs(payload.targets or {}) do
		if t.unit and t.unit:isAlive() and battle:isHostile(unit, t.unit) and server:describeChanges() then queueKnock(unit, t.unit, 1) end
	end
end

-- Knock back everything at the end of this action (the avatar receives it both as the attacker and as the one hit)
function Script:onActionFinished(server, battle, unit, other, payload)
	local list = pendingKnock[unit:unitID()]
	if list == nil then return end
	pendingKnock[unit:unitID()] = nil
	if not unit:isAlive() then return end
	local moved = false
	for _, e in ipairs(list) do
		for _, u in ipairs(battle:getUnitsIf(function(u) return u:unitID() == e.id end)) do
			if u:isAlive() and battle:isHostile(unit, u) and L.adjacent(unit, u) then
				if L.knock(server, battle, unit, u, e.dist) then moved = true end
			end
		end
	end
	if moved and server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
