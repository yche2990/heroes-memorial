local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Searing Aura (H5 Hellmare)
--- Enemies adjacent to this stack take val x (Hellmare count) Fire damage before each action (default 10 per creature); Fire-immune ones take none, Fire resistance reduces it proportionally.
--- "Before acting": the first event of that stack's action (before moving, before striking, wait, defend, cast).
--- Settled by the hidden area script h5AreaZone on all stacks calling Script.onEnemyActs.
--- Parameter: val

local DONE = "h5SearedThisAction"

function Script.onEnemyActs(server, battle, actor)
	if not actor:isAlive() or actor:isGhost() or actor:isTurret() then return end
	if A.markValue(actor, DONE) ~= nil then return end
	A.setMark(server, battle, actor, DONE, 1, 1)
	if not A.damageable(actor) or A.fireImmune(actor) then return end
	local side = actor:getSide()
	local burners = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and battle:isHostile(u, actor) and A.ability(u, "h5SearingAura") ~= nil
			and A.unitDistance(u, actor) == 1
	end)
	table.sort(burners, function(a, b) return a:unitID() < b:unitID() end)
	for _, b in ipairs(burners) do
		if not actor:isAlive() then return end
		local ab = A.ability(b, "h5SearingAura")
		local per = (ab and ab:getVal() > 0) and ab:getVal() or 10
		local dmg = math.floor(per * b:getCount() * (100 - A.fireReduction(actor)) / 100)
		if dmg > 0 then A.hit(server, battle, actor, dmg, "h5/fx/Characters_hits_fire_hit", "FIREBLST") end
	end
end

function Script.onActionDone(server, battle, actor)
	A.clearMark(server, battle, actor, DONE)
end

return Script
