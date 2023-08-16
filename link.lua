help([[
Description
===========
Load link; a ld wrapper for lmod

]])

local name = "${package}"
local version = "${version}"

local dist = pathJoin(os.getenv("ALCOR_DIST"), '..', 'noarch')
local path = pathJoin(dist, name, version)

-- Binary folder
prepend_path("PATH", pathJoin(path, "bin"))
