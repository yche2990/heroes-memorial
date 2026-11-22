local Proxy = require("lib/kadAiProxy")   -- Round 352: precise bonus removal (removal ignores the stacking group, see removeExact)
local Base = require("combat/combatScript")
local Lib = require("heroes-memorial.h7:spells/h7SWLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- The orb itself of Freezing Orb (H7) (added when spells/h7FreezingOrb summons it, hidden).
--- At the end of each round (= the start of the next round, onRoundStart):
---   with moves left: it moves, ignoring obstacles, to the free hex "farthest from the orb and right next to an enemy", then releases another 3x3 frost aura;
---   with no moves left: the orb vanishes.
--- Aura: adjacent enemies (within 1 hex) take val Water damage (hidden spell h7AbFreezingOrbBlast; the engine applies school reduction and immunity),
---       and survivors are slowed by 3 for 3 rounds (hidden spell h7AbWaterChill). War machines, arrow towers and invincible stacks are not hit.
--- Remaining moves are stored as the hidden bonus H7_ORB_H7C on the orb (stacking h7OrbLeft).
--- Parameter: val (damage of each aura, computed from Spell Power at cast time)

local MARK = "H7_ORB_H7C"
local STACK = "h7OrbLeft"

local function markList(unit)
	return unit:getBonuses({ type = MARK }):filter(function(b) return b:getStacking() == STACK end)
end

function Script.getLeft(unit)
	local l = markList(unit)
	if l:size() == 0 then return 0 end
	return l:getBonus(1):getVal()
end

function Script.setLeft(server, battle, unit, n)
	local l = markList(unit)
	if l:size() > 0 then Proxy.removeExact(server, battle, unit, l) end
	server:addUnitBonus(battle, unit, {
		type       = MARK,
		val        = n,
		duration   = ENUM.BonusDuration.oneBattle,
		sourceType = ENUM.BonusSource.other,
		stacking   = STACK,
		hidden     = true
	}, true)
end

local function isEnemyCreature(orb, u)
	return u:isAlive() and not u:isGhost() and not u:isTurret() and u:getSide() ~= orb:getSide()
		and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

--- 3x3 frost aura
function Script.pulse(server, battle, orb, dmg)
	if orb == nil or not orb:isAlive() then return 0 end
	local pos = orb:getPosition()
	local targets = battle:getUnitsIf(function(u)
		return isEnemyCreature(orb, u) and not u:isInvincible() and Lib.unitDistance(u, pos) == 1
	end)
	if #targets == 0 then return 0 end
	local blast, chill = Lib.spell("h7AbFreezingOrbBlast"), Lib.spell("h7AbWaterChill")
	if blast ~= nil then server:castSpell(battle, orb, blast, targets, dmg) end
	local alive = {}
	for _, u in ipairs(targets) do
		if u:isAlive() then table.insert(alive, u) end
	end
	if chill ~= nil and #alive > 0 then server:castSpell(battle, orb, chill, alive, 0) end
	return #targets
end

--- Free hex farthest from the orb and right next to an enemy (nil if none)
function Script.destination(battle, orb)
	local pos = orb:getPosition()
	local best, bestD = nil, 0
	local enemies = battle:getUnitsIf(function(u) return isEnemyCreature(orb, u) end)
	for _, e in ipairs(enemies) do
		local hs = e:getHexes()
		for i = 1, hs:size() do
			for _, n in ipairs(Lib.neighbours(hs:at(i))) do
				if n:isValid() and n:isAvailable() and battle:isAccessibleForUnit(orb, n) then
					local d = Lib.hexDistance(pos, n)
					if d > bestD then best, bestD = n, d end
				end
			end
		end
	end
	return best
end

function Script:onRoundStart(server, battle, unit)
	if not unit:isAlive() or unit:isGhost() then return end
	local left = Script.getLeft(unit)
	if left <= 0 then
		-- No deferred animation before leaving the field (checklist: queued actions of a leaving stack hang the client)
		server:removeUnit(battle, unit)
		server:refreshBattleUnits(battle)
		return
	end
	Script.setLeft(server, battle, unit, left - 1)
	local dest = Script.destination(battle, unit)
	if dest ~= nil then
		server:showBattleAnimation(battle, { { unit = unit } }, "h7/fx/swIceStrikeImpact", "h7/spell_freezing_orb_move_01.ogg", 1.0, true)
		server:moveUnit(battle, unit, dest, true)
		server:refreshBattleUnits(battle)
	end
	Script.pulse(server, battle, unit, self.val or 0)
end

return Script
