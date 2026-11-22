local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Touch of Darkness (Namtaru, see spells/h7wfDarkTouch): put on an ally for 3 rounds.
--- Each enemy hit by its attacks (counterattacks included) takes extra Dark damage of "val per creature x its count" (Dark immunity and magic immunity do not protect).

local S = "h7WarfareDarkTouch"

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload == nil or not unit:isAlive() then return end
	local v = W.effectVal(unit, S)
	if v == nil then return end
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		if t ~= nil and (entry.damage or 0) > 0 and t:isAlive() and t:getSide() ~= unit:getSide() then
			local dealt = W.schoolHit(server, battle, t, v * unit:getCount(), "dark", "h7/fx/h7wfDarkHit")
			if dealt > 0 then W.log(server, battle, 7, { W.name(t) }, { dealt }) end
		end
	end
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if W.effectVal(unit, S) == nil then return end
	W.tickLeft(server, battle, unit, S)
end

return Script
