-- Git integration for nvim-mini

require("git.workflow").setup()

local specs = {}

local function add(spec)
	table.insert(specs, spec)
end

add(require("plugins.git.gitsigns"))
add(require("plugins.git.diffview"))
add(require("plugins.git.flog"))
add(require("plugins.git.fugitive"))

return specs
