local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local L = require("combat/h7dLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Battle-wide script of H7 Magma Pool and Thorns (spells/h7AbZoneD adds one per area with addBattleBonus; every stack inherits a copy).
--- Only handles its own area (obstacle spell = spell, anchor hex index = anchor); does nothing once the obstacle has expired.
---   mode = "magma"  at the start of each round, stacks standing in the pool take power x per Fire damage (resistance and immunity as spell damage)
---   mode = "thorns" at the start of each round, enemies standing in the thorns get Speed -speed (until the start of the next round);
---                   enemies setting off from the thorns or stopping in them after a move take power x per Earth damage (resistance and immunity as spell damage),
---                   never killing the whole stack before or after moving (at most down to 1 health, otherwise the engine's following attack fails).
---                   Thorns do not use the obstacle trigger spell: the engine also triggers it when the stack waits, defends or shoots in place, which does not match "hurt only when moving"
--- The same stack takes damage at most once per round (hidden mark H7_ZONE_HIT_H7C, stacking h7MagmaHit shared with the Magma Pool trigger spell / h7ThornsHit).
--- Parameters: mode, spell (full spell name), anchor, power, per, side (casting side), caster (casting stack id), speed

local HIT = "H7_ZONE_HIT_H7C"

--- Whether unit is an enemy of the caster: by battle:isHostile while the casting stack exists (hypnotized stacks count for their controller, review R1), otherwise by side
function Script:hostile(battle, unit)
	if self.caster then
		local found = battle:getUnitsIf(function(x) return x:unitID() == self.caster and x:isAlive() end)
		if found[1] then
			local ok, r = pcall(function() return battle:isHostile(found[1], unit) end)
			if ok and type(r) == "boolean" then return r end
		end
	end
	return unit:getSide() ~= self.side
end

function Script:myObstacle(battle)
	local key = L.shortKey(self.spell)
	for _, o in ipairs(battle:getAllObstacles() or {}) do
		local s = o:getSpell()
		if s ~= nil and L.shortKey(s:getJsonKey()) == key and L.hexIndex(o:getPosition()) == self.anchor then
			return o
		end
	end
	return nil
end

function Script:inside(battle, unit)
	local key = L.shortKey(self.spell)
	local hs = unit:getHexes()
	for i = 1, hs:size() do
		for _, o in ipairs(battle:getObstaclesOnPos(hs:at(i), false) or {}) do
			local s = o:getSpell()
			if s ~= nil and L.shortKey(s:getJsonKey()) == key and L.hexIndex(o:getPosition()) == self.anchor then
				return true
			end
		end
	end
	return false
end

function Script:hurt(server, battle, unit, mark, logIndex, keepOne)
	if L.findMark(unit, HIT, mark) ~= nil then return end
	local spell = L.spell(L.shortKey(self.spell))
	if spell == nil then return end
	local raw = (self.power or 1) * (self.per or 10)
	local actor = unit
	if self.caster then
		local found = battle:getUnitsIf(function(x) return x:unitID() == self.caster and x:isAlive() end)
		if found[1] then actor = found[1] end
	end
	local dmg = raw
	local ok, adj = pcall(function() return spell:adjustDamage(battle, actor, unit, raw) end)
	if ok and type(adj) == "number" then dmg = adj end
	-- Cannot kill the whole stack before it moves (the engine's "walk over and attack" would report it cannot attack), at most down to 1 health
	if keepOne then dmg = math.min(dmg, unit:getAvailableHealth() - 1) end
	if dmg <= 0 then return end
	server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/h7dBlank", "", 1.0, true)
	local done, killed = server:damageUnit(battle, unit, dmg)
	if unit:isAlive() then L.setMark(server, battle, unit, HIT, 1, 1, mark, true) end
	BattleLog.creaturesPerish(server, battle, unit, killed)
	L.log(server, battle, logIndex, { L.name(unit) }, { done or dmg })
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not L.isReal(unit) or unit:isInvincible() then return end
	if self:myObstacle(battle) == nil or not self:inside(battle, unit) then return end
	if self.mode == "magma" then
		self:hurt(server, battle, unit, "h7MagmaHit", 8)
		server:refreshBattleUnits(battle)
	elseif self.mode == "thorns" and self:hostile(battle, unit) then
		L.setMark(server, battle, unit, "STACKS_SPEED", -(self.speed or 3), 1, "h7ThornsSlow", true)
	end
end

function Script:onBeforeMove(server, battle, unit, other, payload)
	if self.mode ~= "thorns" or battle:getTacticDistance() > 0 then return end
	if not L.isReal(unit) or unit:isInvincible() or not self:hostile(battle, unit) then return end
	if self:myObstacle(battle) == nil or not self:inside(battle, unit) then return end
	self:hurt(server, battle, unit, "h7ThornsHit", 10, true)
end

function Script:onAfterMove(server, battle, unit, other, payload)
	if self.mode ~= "thorns" or battle:getTacticDistance() > 0 then return end
	if not L.isReal(unit) or unit:isInvincible() or not self:hostile(battle, unit) then return end
	if self:myObstacle(battle) == nil or not self:inside(battle, unit) then return end
	self:hurt(server, battle, unit, "h7ThornsHit", 10, true)
	server:refreshBattleUnits(battle)
end

return Script
