local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Passives of the Abyssal Worm (H6 boss):
---   Lava Blood: enemies attacking it in melee take burn Fire damage at the start of each of the next 3 rounds (settled by h6Dot);
---   Evasion: after a melee attack, at the end of this action it moves to a random free hex more than 2 hexes from the attacker and at most 3 hexes from where it stood;
---   Digestion: at the start of each round, stacks it has swallowed (H6_DEVOURED_H6C) take digest damage (ignoring invincibility); they are spat out when the Worm dies.
--- Parameters: burn, digest, animation, sound

-- Evasion does not move the unit in the middle of attack resolution (if it moved away, the attacker would still retaliate and strike the second blow from a distance),
-- so after a melee hit it only remembers the attacker and evades when this action ends (onActionFinished; the worm, being the one hit, receives it), at most once per action.
local pendingDodge = {}

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil or payload.ranged or payload.isCounter then return end
	if other:unitID() == unit:unitID() or not battle:isHostile(unit, other) then return end
	if other:isAlive() and (self.burn or 0) > 0 then
		L.addDot(server, battle, other, "burnWorm" .. tostring(unit:getSide()), self.burn, 3)
	end
	if server:describeChanges() and pendingDodge[unit:unitID()] == nil then pendingDodge[unit:unitID()] = other:unitID() end
end

function Script:onActionFinished(server, battle, unit, other, payload)
	local aid = pendingDodge[unit:unitID()]
	if aid == nil then return end
	pendingDodge[unit:unitID()] = nil
	if not unit:isAlive() then return end
	local att = nil
	for _, u in ipairs(battle:getUnitsIf(function(u) return u:unitID() == aid end)) do att = u end
	-- Evasion
	local here = unit:getPosition()
	local cands = {}
	local all = battle:getAllPossibleHexes()
	for i = 1, all:size() do
		local h = all:at(i)
		if L.hexDistance(h, here) <= 3 and L.hexDistance(h, here) >= 1 and h:isAvailable() and battle:isAccessibleForUnit(unit, h) then
			local far = true
			if att ~= nil and att:isAlive() then
				local oh = att:getHexes()
				for j = 1, oh:size() do if L.hexDistance(oh:at(j), h) < 3 then far = false end end
			end
			if far then cands[#cands + 1] = h end
		end
	end
	if #cands > 0 then
		server:moveUnit(battle, unit, cands[server:rngInt(1, #cands)], true)
		if server:describeChanges() then server:refreshBattleUnits(battle) end
	end
end

local function devoured(battle, unit)
	local id = unit:unitID() + 1
	return battle:getUnitsIf(function(u)
		return u:isAlive() and u:getBonuses({ type = "H6_DEVOURED_H6C" }):filter(function(b) return b:getVal() == id end):size() > 0
	end)
end

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() then return end
	for _, u in ipairs(devoured(battle, unit)) do
		local dealt, killed = L.rawHit(server, battle, u, self.digest or 600, self.animation, self.sound)
		L.log(server, battle, "H6_DEVOURED_H6C", 2, { L.name(u) }, { dealt or 0, killed or 0 })
	end
end

function Script:onDeath(server, battle, unit)
	for _, u in ipairs(devoured(battle, unit)) do
		for _, t in ipairs({ "H6_DEVOURED_H6C", "NOT_ACTIVE", "INVINCIBLE" }) do L.removeByStacking(server, battle, u, t, "h6Devour") end
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
end

return Script
