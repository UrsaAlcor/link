help([[
Description
===========
Load link; a ld wrapper for lmod

]])

local name = "${package}"
local version = "${version}"

function get_noarch_dist(root)
    local frags = {}

    for frag in string.gmatch(root, '/([a-zA-Z0-9]+)') do
        table.insert(frags, frag)
    end

    table.remove(frags)
    table.insert(frags, "noarch")

    local absolute = root:sub(1, 1)
    if absolute ~= '/' then
        print(absolute)
        absolute = ''
    end

    return absolute .. table.concat(frags, '/')
end

local dist = get_noarch_dist(os.getenv("ALCOR_DIST"))
local path = pathJoin(dist, name, version)

-- Binary folder
prepend_path("PATH", pathJoin(path, "bin"))
