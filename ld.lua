#!ALCOR_LUA
unistd = require 'posix.unistd'
lfs    = require 'lfs'

xarg           = {}
explicitrpaths = {}
rpaths         = {}
libpaths       = {}
libs           = {}
static         = {false}
output         = nil
soname         = nil
i              = 1

ALCOR_DIST = os.getenv('ALCOR_DIST') 

--[[
Skip injection logic.
--]]
LD_LUA_BACKEND = os.getenv('LD_LUA_BACKEND') or 'x86_64-linux-gnu-ld.orig'
LD_LUA_BYPASS  = os.getenv('LD_LUA_BYPASS')  or ''
LD_LUA_EXTRA   = os.getenv('LD_LUA_EXTRA')   or ''
LD_LUA_LOGNAME = os.getenv('LD_LUA_LOGNAME')
if LD_LUA_BYPASS ~= '' and LD_LUA_BYPASS ~= '0' then
  unistd.execp(LD_LUA_BACKEND, arg)
end


--[[
Utilities to manipulate paths.
--]]


--[[
Canonicalize paths according to universal rules of path resolution.
--]]
function canonicalize(v)
  --[[
  In the following gsubs, the following patterns are to be understood as follows:
    - '%f[\0/]':  "match the empty string before a / or at the end of the string,
                   except in an empty string"
    - '%f[\0/]/': "match any / except the leading /"
                  
                  This works because the beginning of a string is treated as \0
                  for the purpose of a preceding-character in frontier sets, and
                  thus a frontier set including \0 cannot match at the beginning
                  of a string.
                  
                  Next, including / in the frontier set allows it
                  to match the empty string before a /.
                  
                  Last, we eat that / by requiring it immediately after the
                  frontier set.
  
  The order in which these gsubs are applied matters due to subtle
  interactions between the rules.
  --]]
  v = v:gsub('\0.*$', '')           -- (0)   Embedded NUL bytes illegal inside paths.
  v = v:gsub('/%.%f[\0/]','/')      -- (1)   Delete pointless '/.' segments.
  v = v:gsub('/%.%.%f[\0/]', '\0')  -- (2.1) Replace all '/..' segments by NUL bytes.
  v = v:gsub('^[\0/]+', '/')        -- (2.2) Reduce prefix sequences consisting only
                                    --       of '/' and NUL bytes (ex-'/..' segments)
                                    --       with a single '/'. Any such prefix must
                                    --       be an absolute path that refers to root.
                                    --       Relative paths are unaffected, since by
                                    --       definition they cannot start with a '/'.
  v = v:gsub('\0', '/..')           -- (2.3) Restore non-leading '/..' segments.
  v = v:gsub('/+','/')              -- (3) Delete duplicate /
  v = v:gsub('%f[\0/]/+$','')       -- (4) Delete trailing  / but not leading /
  return v
end


--[[
Search through arguments list and collect libraries and directories for which
rpath injection may be required.
--]]
while arg[i] do
  if     arg[i]          == '-L' then
    i=i+1
    if arg[i] then
      table.insert(libpaths, canonicalize(arg[i]));
    end
  elseif arg[i]:sub(1,3) == '-L/' then
    table.insert(libpaths, canonicalize(arg[i]:sub(3)))
  elseif arg[i]          == '-l' then
    i=i+1
    if not static[1] and arg[i] then
      table.insert(libs, arg[i])
    end
  elseif arg[i]:sub(1,2) == '-l' then
    if not static[1] then
      table.insert(libs, arg[i]:sub(3))
    end
  elseif arg[i] == '-Bstatic' then
    static[1]=true
  elseif arg[i] == '-Bdynamic' then
    static[1]=false
  elseif arg[i] == '--push-state' then
    table.insert(static, 1, static[1])
  elseif arg[i] == '--pop-state' then
    table.remove(static, 1)
  elseif arg[i] == '-dynamic-linker' then
    i=i+1 -- Ignore the dynamic linker
  elseif arg[i] == '-rpath' then
    i=i+1 -- Explicit rpath, record for deduplication
    for v in arg[i]:gmatch('%f[^:\0][^:]+') do -- The -rpath arg can contain multiple paths
      explicitrpaths[canonicalize(v)] = true
    end
  elseif arg[i] == '-o' then
    i=i+1
    output = arg[i]
  elseif arg[i] == '--output' then
    i=i+1
    output = arg[i]
  elseif arg[i]:sub(1,9) == '--output=' then
    output = arg[i]:sub(10)
  elseif arg[i] == '-soname' then
    i=i+1
    soname = arg[i]
  elseif arg[i]:match('[^/]+%.so[^/]*$') then
    local bn = arg[i]:match('[^/]+%.so[^/]*$')
    if arg[i] ~= bn then  -- Not just a raw library name
      table.insert(rpaths, canonicalize(arg[i]:sub(1, -1-#bn)))
    end
  end
  i = i+1 -- Move to next argument
end


--[[
Now, trim the candidate paths to only those that are apparently useful:
That is, they exist and contain a library on the link line.
--]]
founddirs = {}
foundlist = {}
for k,v in pairs(rpaths) do
  if lfs.attributes(v, 'mode') == 'directory' then
    founddirs[v] = true
    table.insert(foundlist, v)
  end
end

foundlibs = {}
for k,v in pairs(libpaths) do
  if lfs.attributes(v, 'mode') == 'directory' then
    for q,name in pairs(libs) do
      if lfs.attributes(v..'/lib'..name..'.so', 'mode') == 'file' then
        foundlibs[name] = true
        if not founddirs[v] then
          founddirs[v] = true
          table.insert(foundlist, v)
        end
      end
    end
  end
end

--[[
Filter the list for whitelisted paths, create the additional -rpath flags
required, and exec the real linker.

There are a few blacklisted paths, mostly pointing to NVIDIA "stubs".
Obviously, these should *never* be used at runtime, so adding them as
-rpath is severely counter-productive.

We normalize paths and check against user-given explicit rpaths to avoid
pointless duplicates.
--]]
for k,v in pairs(foundlist) do
  v = canonicalize(v)
  if v~='' and not explicitrpaths[v] then
    if v:match('^' .. ALCOR_DIST .. '/lz4/') or
       v:match('^' .. ALCOR_DIST .. '/lzma/') or
       v:match('^' .. ALCOR_DIST .. '/zstd/') or
       v:match('^' .. ALCOR_DIST .. '/lmdb/') or
       v:match('^' .. ALCOR_DIST .. '/fftw/') or
       v:match('^' .. ALCOR_DIST .. '/libjpeg%-turbo/') or  -- FFS: A - char must be escaped!
       v:match('^' .. ALCOR_DIST .. '/libpng/') or
       v:match('^' .. ALCOR_DIST .. '/libgif/') or
       v:match('^' .. ALCOR_DIST .. '/libtiff/') or
       v:match('^' .. ALCOR_DIST .. '/libwebp/') or
       v:match('^' .. ALCOR_DIST .. '/liblcms/') or
       v:match('^' .. ALCOR_DIST .. '/openjpeg/') or
       v:match('^' .. ALCOR_DIST .. '/dav1d/') or
       v:match('^' .. ALCOR_DIST .. '/x264/') or
       v:match('^' .. ALCOR_DIST .. '/x265/') or
       v:match('^' .. ALCOR_DIST .. '/libmp3lame/') or
       v:match('^' .. ALCOR_DIST .. '/cuda/') or
       v:match('^' .. ALCOR_DIST .. '/cudnn/') or
       v:match('^' .. ALCOR_DIST .. '/nccl/') or
       v:match('^' .. ALCOR_DIST .. '/magma/') or
       v:match('^' .. ALCOR_DIST .. '/oneapi/') or
       v:match('^' .. ALCOR_DIST .. '/openblas/') or
       LD_LUA_EXTRA:match('%f[^:\0]'..v) then
      if not v:match('^' .. ALCOR_DIST .. '/cuda/.+/stubs/*$') and
         not v:match('^' .. ALCOR_DIST .. '/tensorrt/.+/stubs/*$') then
        table.insert(xarg, '-rpath')
        table.insert(xarg, v)
        explicitrpaths[v] = true
      end
    end
  end
end
arg = table.move(xarg, 1, #xarg, #arg+1, arg)


--[[
Finishing hack: The libfftw3f?_*.so.* libraries (but not libfftw3f?.so.* itself)
bake into themselves an absolute path to their install location, to find
libfftw3.so.*. Punch out and replace such paths with $ORIGIN, making them
relocatable.
--]]
if soname and soname:match('^libfftw3f?_.+%.so%.%d+$') then
  i=1
  while arg[i] do
    if arg[i] == '-rpath' and
       arg[i+1]           and
       arg[i+1]:match('^' .. ALCOR_DIST .. '/fftw/+[^/]+/+lib') then
      arg[i+1] = '$ORIGIN'
      i = i+2
    else
      i = i+1
    end
  end
end


--[[
Execute linker.
If logging enabled, append the final link line into the logfile.
--]]
if LD_LUA_LOGNAME then
  local s = LD_LUA_BACKEND..' '..table.concat(arg, ' ')..'\n'
  local f <close> = io.open(LD_LUA_LOGNAME, 'a+')
  f:write(s) -- In one atomic write, append.
  f:flush()
end
unistd.execp(LD_LUA_BACKEND, arg)
