local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Hidden abilities of H7 warfare units (round 428):
---   * Death: the hidden original war machine dies too (lost after battle as in the original; the Catapult is never lost).
---   * Siege units on "Defend": automatic catapult shots (the engine's automatic catapult and the AI / auto-combat only know the original Catapult, so H7 siege units shoot from here).
---     Clicking the walls manually goes through the engine as usual; Defend = let the AI shoot, with shots and hit chances as the original Catapult (by Ballistics level), level 5 one shot more.

-- Catapult (catapultShot) per level, with the values actually in effect (engine original + hota balance catapultHotA.json: Basic and Advanced 60 on the gate, Expert 100 on all four);
-- if catapultShot changes, keep this and h7wfCatapultShot5 in warfareSpells.json in sync (catapult5 in the generator gen_h7warfare.py uses the same numbers).
-- Shots per round, hit chance per part (keep / gate / towers / walls), chance of 1 or 2 damage on a hit (otherwise 0)
local SHOTS = { [0] = 1, [1] = 1, [2] = 2, [3] = 2 }
local HIT = {
	[0] = { keep = 5, gate = 25, tower = 10, wall = 50 },
	[1] = { keep = 7, gate = 60, tower = 15, wall = 60 },
	[2] = { keep = 7, gate = 60, tower = 15, wall = 60 },
	[3] = { keep = 100, gate = 100, tower = 100, wall = 100 },
}
local NORMAL = { [0] = 60, [1] = 50, [2] = 50, [3] = 0 }
local CRIT = { [0] = 30, [1] = 50, [2] = 50, [3] = 100 }
local PARTS = { keep = "keep", bottomTower = "tower", upperTower = "tower", gate = "gate",
	bottomWall = "wall", belowGate = "wall", overGate = "wall", upperWall = "wall" }

function Script:onDeath(server, battle, unit, other, payload)
	if unit:isGhost() then return end
	W.killOriginal(server, battle, W.original(battle, unit))
end

local function autoCatapult(server, battle, G)
	local O = W.original(battle, G)
	local src = O or G
	local lv = math.max(0, math.min(3, W.skill(src, "ballistics")))
	local shots = SHOTS[lv] + ((W.mark(G, W.LEVEL) == 5) and 1 or 0)
	for _ = 1, shots do
		local parts = {}
		for name, kind in pairs(PARTS) do
			local p = ENUM.WallPart[name]
			if p ~= nil and battle:isWallPartAttackable(p) and (battle:getWallState(p) or 0) > 0 then parts[#parts + 1] = { p, kind } end
		end
		if #parts == 0 then return end
		table.sort(parts, function(a, b) return a[1] < b[1] end)
		local pick = parts[server:rngInt(1, #parts)]
		if server:rngInt(1, 100) <= HIT[lv][pick[2]] then
			local r = server:rngInt(1, 100)
			local dmg = (r <= CRIT[lv]) and 2 or ((r <= CRIT[lv] + NORMAL[lv]) and 1 or 0)
			if dmg > 0 then server:catapultAttack(battle, G, pick[1], dmg) end
		end
	end
end

function Script:onDefend(server, battle, unit, other, payload)
	if unit:isGhost() or not unit:isAlive() then return end
	if not unit:hasBonuses({ type = "CATAPULT" }) then return end
	if battle:getDefendedTown() == nil then return end
	autoCatapult(server, battle, unit)
end

return Script
