local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 warfare unit, Shadow Lurker Terrifying Visions (round 428).
--- Enemies hit by its shot take Dark damage of "this shot's damage x 40%" at the start of each of the next 2 rounds (Dark immunity and magic immunity do not protect,
--- Dark damage reduction applies). Another hit only refreshes the rounds, keeping the larger value. Settled in combat/h7WarfareHarrow (on the target).

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload == nil or payload.isCounter or not payload.ranged or not unit:isAlive() then return end
	local pct, turns = W.SKILL.harrowPct, W.SKILL.harrowTurns
	local hit = {}
	for _, entry in ipairs(payload.targets or {}) do
		local t = entry.unit
		local dmg = entry.damage or 0
		if t ~= nil and dmg > 0 and t:isAlive() and not t:isGhost() and t:getSide() ~= unit:getSide()
			and not t:hasBonuses({ type = "SIEGE_WEAPON" }) then
			local v = math.floor(dmg * pct / 100)
			if v > 0 then
				W.setEffect(server, battle, t, "h7WarfareHarrow", v, turns, "h7/abilities/h7wfHarrowingVision")
				hit[#hit + 1] = { unit = t }
			end
		end
	end
	if #hit > 0 then
		server:showBattleAnimation(battle, hit, "h7/fx/h7wfHarrow", "", 1.0, true)
		server:refreshBattleUnits(battle)
	end
end

return Script
