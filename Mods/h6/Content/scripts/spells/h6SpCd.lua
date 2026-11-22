--- H6 memorial hero spells: cooldown / once per battle (as h6dynOnce of the Dynasty Weapons, marks kept per casting side).
--- Written into the same spell as its effects: if its side has used it (or it is on cooldown), applicableGeneral returns false and the whole spell cannot be cast; it is recorded when cast.
--- Parameters: index (unique within this mod), cooldown (0 = once per battle; N = cannot be used for N rounds after casting)
--- Marks: once-per-battle sits on the battlefield (inherited by both sides' stacks); cooldowns sit on every living stack at that moment (N_TURNS; battlefield bonuses do not count down by rounds),
---       and it is on cooldown while any of them still carries it. val = index x 10 + casting side.
local Base = require("spells/spellEffect")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script
local CD = "H6_SPELL_CD_H6C"

local function code(side, index) return index * 10 + (side or 0) end

local function used(battle, side, index)
	local c = code(side, index)
	local found = false
	battle:getUnitsIf(function(u)    -- The predicate is also called for dead stacks, so all are scanned through a side effect
		if not found then
			local list = u:getBonuses({ type = CD })
			for i = 1, list:size() do
				if list:getBonus(i):getVal() == c then found = true; break end
			end
		end
		return false
	end)
	return found
end

function Script:applicableGeneral(mechanics, problem)
	if used(mechanics:getBattle(), mechanics:getCasterSide() or 0, self.index or 0) then
		problem:addGeneric(mechanics)
		return false
	end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end
function Script:transformTarget(mechanics, aimPoint, spellTarget) return spellTarget end
function Script:filterTarget(mechanics, target) return target end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end      -- Not recorded in the AI simulation
	local battle = mechanics:getBattle()
	local c = code(mechanics:getCasterSide() or 0, self.index or 0)
	local d = { type = CD, val = c, duration = "ONE_BATTLE", sourceType = "OTHER", stacking = "h6SpCd" .. c, hidden = true }
	if (self.cooldown or 0) > 0 then
		d.duration = "N_TURNS"; d.turns = self.cooldown + 1
		for _, u in ipairs(battle:getUnitsIf(function(u) return u:isAlive() end)) do server:addUnitBonus(battle, u, d, false) end
		return
	end
	server:addBattleBonus(battle, d)
end

return Script
