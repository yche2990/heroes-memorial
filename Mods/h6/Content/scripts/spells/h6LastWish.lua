local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Last Wish (H6 Michael): uses up the corpse of a guard (minion) and sends rays from there in 6 directions to the edge of the battlefield;
--- every enemy on the rays takes per Light damage (scaled by Light and all-spell reduction). Cannot be cast without a guard corpse (which is why Michael becomes enraged, see h6Enrage).
--- Parameters: per, minion, key, animation, sound


function Script:corpses(mechanics)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local ids = {}
	for _, id in ipairs(self.minion or {}) do ids[id] = true end
	return battle:getUnitsIf(function(u)
		return u:getSide() == caster:getSide() and not u:isAlive() and not u:isGhost() and ids[u:getCreature():getJsonKey()] == true
	end)
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or #self:corpses(mechanics) == 0 then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local list = self:corpses(mechanics)
	if caster == nil or #list == 0 then return end
	local corpse = list[server:rngInt(1, #list)]
	local c = corpse:getPosition()
	local hexes = L.hexTable(battle)
	local hit = {}
	-- 6 directions: take the 6 neighbours of c and extend along the line c -> neighbour
	local neigh = {}
	for _, h in pairs(hexes) do if L.hexDistance(h, c) == 1 then neigh[#neigh + 1] = h end end
	for _, n in ipairs(neigh) do
		for k = 1, 20 do
			local idx = L.lineIndex(c, n, k)
			local h = idx and hexes[idx]
			if h == nil then break end
			local u = battle:getUnitByPos(h, true)
			if u and L.real(u) and battle:isHostile(caster, u) then hit[u:unitID()] = u end
		end
	end
	local total, n = 0, 0
	for _, u in pairs(hit) do
		n = n + 1
		local a = math.floor((self.per or 1250) * (100 - L.schoolReduction(u, "01lightSchool")) / 100)
		total = total + (L.hit(server, battle, u, a, self.animation, self.sound) or 0)
	end
	if not Proxy.trial(server) then server:removeUnit(battle, corpse) end   -- Round 419: the AI simulation does not remove corpses on the imaginary battlefield
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 9, { L.name(caster) }, { n, total })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
