local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Death Cloak (Faceless, see spells/h7wfCloak): put on an ally until the end of this round.
--- The next enemy to attack it in melee (counterattacks included) first takes val Dark damage, and the cloak vanishes.
--- Level 5 (mark h7Wf:h7WarfareCloak|burst): if the cloak is still there at the end of the round, it explodes on all surrounding enemies for burst Dark damage each.
--- There is no end-of-round event, so it is settled at the start of the next round (before any stack acts).

local S = "h7WarfareCloak"
local BURST = "h7Wf:h7WarfareCloak|burst"

local function clear(server, battle, unit)
	W.clearEffect(server, battle, unit, S)
	W.clearMark(server, battle, unit, BURST)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if payload == nil or payload.ranged or other == nil or not unit:isAlive() then return end
	if other:getSide() == unit:getSide() then return end
	local v = W.effectVal(unit, S)
	if v == nil then return end
	clear(server, battle, unit)
	local dealt = W.schoolHit(server, battle, other, v, "dark", "h7/fx/h7wfDarkHit")
	if dealt > 0 then W.log(server, battle, 5, { W.name(other) }, { dealt }) end
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if W.effectVal(unit, S) == nil then return end
	local burst = W.mark(unit, BURST)
	clear(server, battle, unit)
	if burst == nil or burst <= 0 or not unit:isAlive() then return end
	local side = unit:getSide()
	local list = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and u:getSide() ~= side
	end)
	local Ab = require("spells/h7abLib")
	for _, u in ipairs(list) do
		if Ab.adjacent(unit, u) then
			local dealt = W.schoolHit(server, battle, u, burst, "dark", "h7/fx/h7wfCloakBurst")
			if dealt > 0 then W.log(server, battle, 6, { W.name(u) }, { dealt }) end
		end
	end
end

return Script
