--- H7 Piercing Shot, Fire (Apprentice, Mage Disciple): same as combat/h7PiercingShot, with Fire piercing damage.
--- No parameters; fire = true fixed.
local Pierce = require("combat/h7PiercingShot")
local Script = setmetatable({ fire = true }, {__index = Pierce})
Script.__index = Script

return Script
