--- Frenzy (H6): the target (friend or foe) immediately attacks the nearest other stack (not using its action, no counterattack) with +pct% damage. Parameter: pct (4 numbers)
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function nearest(battle, u)
	local best, bd = nil, 1000
	for _, x in ipairs(battle:getUnitsIf(function(x) return L.real(x) and x:unitID() ~= u:unitID() end)) do
		local d = L.unitDistance(u, x)
		if d < bd then best, bd = x, d end
	end
	return best
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local pct = 100 + S.pick(mechanics, self.pct)
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local v = nearest(battle, u)
			if v then
				if Proxy.trial(server) then
					Proxy.damage(server, battle, v, Proxy.attackEstimate(u, v, pct, false), {})
				else
					L.hit(server, battle, v, L.attackDamage(server, u, v, pct, false), nil, nil)
				end
			end
		end
	end
end
if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
