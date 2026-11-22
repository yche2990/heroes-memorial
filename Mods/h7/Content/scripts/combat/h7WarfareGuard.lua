local Base = require("combat/combatScript")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- War machines of the guards of the H7 Memorial Smithy (heroes-memorial.h7:h7WarfareSmithy) (round 428).
--- The guards are one stack each of the basic creatures of levels 1-7 of one H7 faction (all 7 slots), without a hero, so no war machine artifacts; this script sits on the 14 basic champion creatures
--- (hidden, parameters faction = faction, army = basic creatures of levels 1-6 of that faction, comma-separated); during battle setup it adds that faction's H7 warfare units to the defender, fixed at level 5:
--- the ranged and support slots are filled (no walls in the field, so no siege slot).
--- Only triggers when all of the following hold, which ordinary wandering monsters and hero armies never match exactly: its side has no hero; its side's stacks (alive, excluding summons,
--- clones, arrow towers and war machines) are exactly 7: one each of the 6 kinds in army + this stack.

-- Positions of the original war machines on the defender's side (engine BattleInfo: defender Ballista 66, Ammo Cart 32, First Aid Tent 168)
local HEX = { ballista = 66, cart = 32, tent = 168 }

local function real(u, side)
	return u:isAlive() and u:getSide() == side and not u:isClone() and not u:copy():isSummoned() and not u:isTurret()
		and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

function Script:onBattleSetup(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isClone() or unit:copy():isSummoned() then return end
	if type(self.faction) ~= "string" or type(self.army) ~= "string" then return end
	if unit:hasBonuses({ type = "PRIMARY_SKILL", sourceType = ENUM.BonusSource.heroBaseSkill }) then return end
	local units = W.UNITS[self.faction]
	if units == nil then return end
	local side = unit:getSide()
	local need = {}
	for k in self.army:gmatch("[^,%s]+") do need[W.bare(k)] = 1 end
	need[W.creatureKey(unit)] = 1
	local list = battle:getUnitsIf(function(u) return real(u, side) end)
	if #list ~= 7 then return end
	for _, u in ipairs(list) do
		local k = W.creatureKey(u)
		if need[k] ~= 1 then return end
		need[k] = 0
	end
	for _, v in pairs(need) do if v ~= 0 then return end end
	-- Already added (the other champion carries this script too, but a guard has only one champion; checked again to be safe)
	if #battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side and W.isWarfare(u) end) > 0 then return end
	local hexes = {}
	local arr = battle:getAllPossibleHexes()
	for i = 1, arr:size() do
		local h = arr:at(i)
		hexes[h:getX() + h:getY() * 17] = h
	end
	local shown = {}
	for _, slot in ipairs({ "ballista", "cart", "tent" }) do
		local key = units[slot]
		if key ~= nil then
			if W.LV5[key] then key = W.LV5[key] end
			local hex = hexes[HEX[slot]]
			local G = W.spawn(server, battle, side, hex, key, 1)
			if G ~= nil then
				W.applyLevel(server, battle, G, key, 5, 0)
				shown[#shown + 1] = { hex = G:getPosition() }
			end
		end
	end
	if #shown > 0 then
		server:showBattleAnimation(battle, shown, "h7/fx/h7wfDeploy", "", 1.0)
		server:refreshBattleUnits(battle)
	end
end

return Script
