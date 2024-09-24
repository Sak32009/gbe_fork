require("premake", ">=5.0.0-beta2")

-- ##################################################
-- #################### WARNING! ####################
-- Don't forget to set the CMAKE_GENERATOR environment variable to one of the following values:
-- https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html#manual:cmake-generators(7)
-- ##################################################
-- Common generators:
-- Unix Makefiles
-- Visual Studio 17 2022
-- MSYS Makefiles
-- ##################################################

-- ##################################################
-- CHECK OS TARGET
-- ##################################################

if not (os.target() == "windows" or os.target() == "linux") then
  error('Unsupported os target: "' .. os.target() .. '"')
end

-- ##################################################
-- SET OPTIONS GENERAL
-- ##################################################

newoption {
  category = "general",
  trigger = "verbose",
  description = "Verbose output",
}

newoption {
  category = "general",
  trigger = "clean",
  description = "Cleanup before any action",
}

-- ##################################################
-- SET OPTIONS TOOLS
-- ##################################################

newoption {
  category = "tools",
  trigger = "custom-cmake",
  description = "Use custom cmake",
  value = 'path/to/cmake.exe',
  default = nil
}

newoption {
  category = "tools",
  trigger = "cmake-toolchain",
  description = "Use cmake toolchain",
  value = 'path/to/toolchain.cmake',
  default = nil
}

-- ##################################################
-- SET OPTIONS BUILD
-- ##################################################

newoption {
  category = "build",
  trigger = "all-build",
  description = "Build all deps",
}

newoption {
  category = "build",
  trigger = "j",
  description = "Parallel build jobs, by default the max possible",
}

newoption {
  category = "build",
  trigger = "32-build",
  description = "Build for 32-bit arch",
}

newoption {
  category = "build",
  trigger = "64-build",
  description = "Build for 64-bit arch",
}

newoption {
  category = "build",
  trigger = "build-curl",
  description = "Build curl",
}

newoption {
  category = "build",
  trigger = "build-ingame_overlay",
  description = "Build ingame_overlay",
}

newoption {
  category = "build",
  trigger = "build-libssq",
  description = "Build libssq",
}

newoption {
  category = "build",
  trigger = "build-mbedtls",
  description = "Build mbedtls",
}

newoption {
  category = "build",
  trigger = "build-protobuf",
  description = "Build protobuf",
}

newoption {
  category = "build",
  trigger = "build-zlib",
  description = "Build zlib",
}

-- ##################################################
-- FUNCTIONS
-- ##################################################

local function merge_list(src, dest)
  local res = {}
  for _, v in ipairs(src) do
    table.insert(res, v)
  end
  for _, v in ipairs(dest) do
    table.insert(res, v)
  end
  return res
end

-- ##################################################
-- CHECK BUILD -j OPTION
-- ##################################################

if _OPTIONS['j'] and not tonumber(_OPTIONS['j']) then
  error('Invalid argument for --j: "' .. _OPTIONS['j'] .. '"')
end

-- ##################################################
-- COMMON DEFS
-- ##################################################

local cwd = os.getcwd()

local deps_action_dir = path.join(cwd, 'build', 'deps', os.target(), _ACTION)

local third_party_dir = path.join(cwd, 'third-party')
local third_party_deps_dir = path.join(third_party_dir, 'deps')
local third_party_tools_dir = path.join(third_party_dir, 'tools', os.target())
local third_party_tool_cmake_file = path.join(third_party_tools_dir, 'cmake', 'dist', 'bin', 'cmake')

-- ##################################################
-- CHECK CMAKE
-- ##################################################

if _OPTIONS["custom-cmake"] then
  third_party_tool_cmake_file = _OPTIONS["custom-cmake"]
  print('Using custom cmake: "' .. _OPTIONS["custom-cmake"] .. '"')
else
  if os.host() == 'windows' then
    third_party_tool_cmake_file = third_party_tool_cmake_file .. '.exe'
  end
  print('Using cmake: "' .. third_party_tool_cmake_file .. '"')
end

if not os.isfile(third_party_tool_cmake_file) then
  error('cmake is missing: "' .. third_party_tool_cmake_file .. '"')
end

-- ##################################################
-- CMAKE DEFS
-- ##################################################

-- https://cmake.org/cmake/help/latest/variable/CMAKE_LANG_FLAGS_CONFIG.html#variable:CMAKE_%3CLANG%3E_FLAGS_%3CCONFIG%3E
local cmake_common_defs = {
  'CMAKE_BUILD_TYPE=Release',
  'CMAKE_POSITION_INDEPENDENT_CODE=True',
  'BUILD_SHARED_LIBS=OFF',
  'CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
}

-- ##################################################
-- CMAKE FUNCTIONS
-- ##################################################

local function cmake_copy(dep_folder)
  local dep_action_dir = path.join(deps_action_dir, dep_folder)
  local dep_src_dir = path.join(third_party_deps_dir, dep_folder, 'src')

  if not os.isdir(dep_src_dir) then
    error('Dep src is missing: "' .. dep_src_dir .. '"')
  end

  if _OPTIONS["clean"] then
    print('Cleaning dir: "' .. dep_action_dir .. '"')
    os.rmdir(dep_action_dir)
  end

  print('Creating dir: "' .. dep_action_dir .. '"')
  local ok_mk, err_mk = os.mkdir(dep_action_dir)
  if not ok_mk then
    error('Failed to create dir: "' .. err_mk .. '"')
  end

  -- the weird "/*" at the end is not a mistake, premake uses cp cpmmand on linux, which won't copy inner dir otherwise
  local ok_execute = os.execute('{COPYDIR} "' .. dep_src_dir .. '"/* "' .. dep_action_dir .. '"')
  if not ok_execute then
    error('Failed to copy dir: src="' .. dep_src_dir .. '" | dest="' .. dep_action_dir .. '"')
  end
end

local function cmake_build(dep_folder, is_32, extra_cmd_defs, c_flags_init, cxx_flags_init)
  local build_arch = iif(is_32, '32', '64')

  local dep_action_dir = path.join(deps_action_dir, dep_folder)
  local dep_action_buildarch_dir = path.join(dep_action_dir, 'build' .. build_arch)
  local dep_action_installarch_dir = path.join(dep_action_dir, 'install' .. build_arch)

  print('')
  print('')
  print('Building dep: "' .. dep_action_dir .. '"')

  -- clean
  if _OPTIONS["clean"] then
    print('Cleaning dir: "' .. dep_action_buildarch_dir .. '"')
    os.rmdir(dep_action_buildarch_dir)
    print('Cleaning dir: "' .. dep_action_installarch_dir .. "'")
    os.rmdir(dep_action_installarch_dir)
  end

  -- create dirs
  print('Creating dir: "' .. dep_action_buildarch_dir .. '"')
  local ok_mk, err_mk = os.mkdir(dep_action_buildarch_dir)
  if not ok_mk then
    error('Failed to create dir: "' .. err_mk .. '"')
  end

  print('Creating dir: "' .. dep_action_installarch_dir .. '"')
  local ok_mk, err_mk = os.mkdir(dep_action_installarch_dir)
  if not ok_mk then
    error('Failed to create dir: "' .. err_mk .. '"')
  end

  -- cmake generate
  local cmake_common_defs_str = '-D' ..
      table.concat(cmake_common_defs, ' -D') .. ' -DCMAKE_INSTALL_PREFIX="' .. dep_action_installarch_dir .. '"'
  local cmd_gen = third_party_tool_cmake_file ..
      ' -S "' .. dep_action_dir .. '" -B "' .. dep_action_buildarch_dir .. '" ' .. cmake_common_defs_str

  local all_cflags_init = {}
  local all_cxxflags_init = {}

  -- c/cxx init flags based on arch/action
  if string.match(_ACTION, 'gmake.*') then
    if is_32 then
      table.insert(all_cflags_init, '-m32')
      table.insert(all_cxxflags_init, '-m32')
    end
  elseif string.match(_ACTION, 'vs.+') then
    -- these 2 are needed because mbedtls doesn't care about 'CMAKE_MSVC_RUNTIME_LIBRARY' for some reason
    table.insert(all_cflags_init, '/MT')
    table.insert(all_cflags_init, '/D_MT')

    table.insert(all_cxxflags_init, '/MT')
    table.insert(all_cxxflags_init, '/D_MT')

    local cmake_generator = os.getenv("CMAKE_GENERATOR") or ""
    if cmake_generator == "" and os.host() == 'windows' or cmake_generator:find("Visual Studio") then
      if is_32 then
        cmd_gen = cmd_gen .. ' -A Win32'
      else
        cmd_gen = cmd_gen .. ' -A x64'
      end
    end
  else
    error('Unsupported action for cmake build: "' .. _ACTION .. '"')
  end

  -- add c/cxx extra init flags
  if c_flags_init then
    if type(c_flags_init) ~= 'table' then
      error('Unsupported type for c_flags_init: "' .. type(c_flags_init) .. '"')
    end
    for _, cval in pairs(c_flags_init) do
      table.insert(all_cflags_init, cval)
    end
  end

  if cxx_flags_init then
    if type(cxx_flags_init) ~= 'table' then
      error('Unsupported type for cxx_flags_init: "' .. type(cxx_flags_init) .. '"')
    end
    for _, cval in pairs(cxx_flags_init) do
      table.insert(all_cxxflags_init, cval)
    end
  end

  -- convert to space-delimited str
  local cflags_init_str = ''
  if #all_cflags_init > 0 then
    cflags_init_str = table.concat(all_cflags_init, " ")
  end

  local cxxflags_init_str = ''
  if #all_cxxflags_init > 0 then
    cxxflags_init_str = table.concat(all_cxxflags_init, " ")
  end

  -- write toolchain file
  local toolchain_file_content = ''

  if _OPTIONS["cmake-toolchain"] then
    toolchain_file_content = 'include(' .. _OPTIONS["cmake-toolchain"] .. ')\n\n'
  end

  if #cflags_init_str > 0 then
    toolchain_file_content = toolchain_file_content .. 'set(CMAKE_C_FLAGS_INIT "' .. cflags_init_str .. '" )\n'
  end

  if #cxxflags_init_str > 0 then
    toolchain_file_content = toolchain_file_content .. 'set(CMAKE_CXX_FLAGS_INIT "' .. cxxflags_init_str .. '" )\n'
  end

  if string.match(_ACTION, 'vs.+') then -- because libssq doesn't care about CMAKE_C/XX_FLAGS_INIT
    toolchain_file_content = toolchain_file_content ..
        'set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} /MT /D_MT" ) \n'
    toolchain_file_content = toolchain_file_content ..
        'set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} /MT /D_MT" ) \n'
  end

  if #toolchain_file_content > 0 then
    local toolchain_file = path.join(dep_action_dir,
      'toolchain_' .. tostring(is_32) .. '_' .. _ACTION .. '_' .. os.target() .. '.precmt')
    if not io.writefile(toolchain_file, toolchain_file_content) then
      error('Failed to write cmake toolchain: "' .. toolchain_file .. '"')
    end
    cmd_gen = cmd_gen .. ' -DCMAKE_TOOLCHAIN_FILE="' .. toolchain_file .. '"'
  end

  -- add extra defs
  if extra_cmd_defs then
    if type(extra_cmd_defs) ~= 'table' then
      error('Unsupported type for extra_cmd_defs: "' .. type(extra_cmd_defs) .. '"')
    end
    if #extra_cmd_defs > 0 then
      local extra_defs_str = ' -D' .. table.concat(extra_cmd_defs, ' -D')
      cmd_gen = cmd_gen .. extra_defs_str
    end
  end

  if _OPTIONS['verbose'] then
    print(cmd_gen)
  end

  local ok_execute_generate = os.execute(cmd_gen)
  if not ok_execute_generate then
    error("Failed to generate!")
  end

  -- cmake build
  local parallel_build_str = ' --parallel' .. iif(_OPTIONS['j'], ' ' .. _OPTIONS['j'], '')
  local verbose_build_str = iif(_OPTIONS['verbose'], ' -v', '')

  local cmd_build = third_party_tool_cmake_file ..
      ' --build "' .. dep_action_buildarch_dir .. '" --config Release' .. parallel_build_str .. verbose_build_str

  if _OPTIONS['verbose'] then
    print(cmd_build)
  end

  local ok_execute_build = os.execute(cmd_build)
  if not ok_execute_build then
    error("Failed to build!")
  end

  -- cmake install
  local cmd_install = third_party_tool_cmake_file ..
      ' --install "' .. dep_action_buildarch_dir .. '" --prefix "' .. dep_action_installarch_dir .. '"'

  if _OPTIONS['verbose'] then
    print(cmd_install)
  end

  local ok_execute_install = os.execute(cmd_install)
  if not ok_execute_install then
    error("Failed to install!")
  end
end

-- ##################################################
-- SET CHMOD TOOLS
-- ##################################################

if os.host() == "linux" then
  if not _OPTIONS["custom-cmake"] then
    local ok_chmod, err_chmod = os.chmod(third_party_tool_cmake_file, "777")
    if not ok_chmod then
      error('Cannot chmod: "' .. err_chmod .. '"')
    end
  end
end

-- ##################################################
-- BUILD libssq
-- ##################################################

if _OPTIONS["build-libssq"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('libssq')

  -- build
  if _OPTIONS["32-build"] then
    cmake_build('libssq', true)
  end

  if _OPTIONS["64-build"] then
    cmake_build('libssq', false)
  end
end

-- ##################################################
-- BUILD zlib
-- ##################################################

if _OPTIONS["build-zlib"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('zlib')

  -- build
  if _OPTIONS["32-build"] then
    cmake_build('zlib', true)
  end

  if _OPTIONS["64-build"] then
    cmake_build('zlib', false)
  end
end

-- ############## zlib is painful ##############
-- lib curl uses the default search paths, even when ZLIB_INCLUDE_DIR and ZLIB_LIBRARY_RELEASE are defined
-- check thir CMakeLists.txt line #573
--     optional_dependency(ZLIB)
--     if(ZLIB_FOUND)
--       set(HAVE_LIBZ ON)
--       set(USE_ZLIB ON)
--
--       # Depend on ZLIB via imported targets if supported by the running
--       # version of CMake.  This allows our dependents to get our dependencies
--       # transitively.
--       if(NOT CMAKE_VERSION VERSION_LESS 3.4)
--         list(APPEND CURL_LIBS ZLIB::ZLIB)    <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< evil
--       else()
--         list(APPEND CURL_LIBS ${ZLIB_LIBRARIES})
--         include_directories(${ZLIB_INCLUDE_DIRS})
--       endif()
--       list(APPEND CMAKE_REQUIRED_INCLUDES ${ZLIB_INCLUDE_DIRS})
--     endif()
-- we have to set the ZLIB_ROOT so that it is prepended to the search list
-- we have to set ZLIB_LIBRARY NOT ZLIB_LIBRARY_RELEASE in order to override the FindZlib module
-- we also should set ZLIB_USE_STATIC_LIBS since we want to force static builds
-- https://github.com/Kitware/CMake/blob/a6853135f569f0b040a34374a15a8361bb73901b/Modules/FindZLIB.cmake#L98C4-L98C13

local zlib_name = ''
local mbedtls_name = ''
local mbedcrypto_name = ''
local mbedx509_name = ''

-- name
if _ACTION and os.target() == 'windows' then
  if string.match(_ACTION, 'vs.+') then
    zlib_name = 'zlibstatic'
    mbedtls_name = 'mbedtls'
    mbedcrypto_name = 'mbedcrypto'
    mbedx509_name = 'mbedx509'
  elseif string.match(_ACTION, 'gmake.*') then
    zlib_name = 'libzlibstatic'
    mbedtls_name = 'libmbedtls'
    mbedcrypto_name = 'libmbedcrypto'
    mbedx509_name = 'libmbedx509'
  else
    error('Unsupported os target/action: ' .. os.target() .. ' / ' .. _ACTION)
  end
else -- linux or macos
  zlib_name = 'libz'
  mbedtls_name = 'libmbedtls'
  mbedcrypto_name = 'libmbedcrypto'
  mbedx509_name = 'mbedx509'
end

-- extension
if _ACTION and string.match(_ACTION, 'vs.+') then
  zlib_name = zlib_name .. '.lib'
  mbedtls_name = mbedtls_name .. '.lib'
  mbedcrypto_name = mbedcrypto_name .. '.lib'
  mbedx509_name = mbedx509_name .. '.lib'
else
  zlib_name = zlib_name .. '.a'
  mbedtls_name = mbedtls_name .. '.a'
  mbedcrypto_name = mbedcrypto_name .. '.a'
  mbedx509_name = mbedx509_name .. '.a'
end

local wild_zlib_path_32 = path.join(deps_action_dir, 'zlib', 'install32', 'lib', zlib_name)
local wild_zlib_32 = {
  'ZLIB_USE_STATIC_LIBS=ON',
  'ZLIB_ROOT="' .. path.join(deps_action_dir, 'zlib', 'install32') .. '"',
  'ZLIB_INCLUDE_DIR="' .. path.join(deps_action_dir, 'zlib', 'install32', 'include') .. '"',
  'ZLIB_LIBRARY="' .. wild_zlib_path_32 .. '"',
}
local wild_zlib_path_64 = path.join(deps_action_dir, 'zlib', 'install64', 'lib', zlib_name)
local wild_zlib_64 = {
  'ZLIB_USE_STATIC_LIBS=ON',
  'ZLIB_ROOT="' .. path.join(deps_action_dir, 'zlib', 'install64') .. '"',
  'ZLIB_INCLUDE_DIR="' .. path.join(deps_action_dir, 'zlib', 'install64', 'include') .. '"',
  'ZLIB_LIBRARY="' .. wild_zlib_path_64 .. '"',
}

-- ##################################################
-- BUILD mbedtls
-- ##################################################

if _OPTIONS["build-mbedtls"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('mbedtls')

  -- set defs
  local mbedtls_common_defs = {
    "USE_STATIC_MBEDTLS_LIBRARY=ON",
    "USE_SHARED_MBEDTLS_LIBRARY=OFF",
    "ENABLE_TESTING=OFF",
    "ENABLE_PROGRAMS=OFF",
    "MBEDTLS_FATAL_WARNINGS=OFF",
  }

  if os.target() == 'windows' and string.match(_ACTION, 'vs.+') then
    table.insert(mbedtls_common_defs, "MSVC_STATIC_RUNTIME=ON")
  else -- linux or macos or MinGW on Windows
    table.insert(mbedtls_common_defs, "LINK_WITH_PTHREAD=ON")
  end

  -- build
  if _OPTIONS["32-build"] then
    local mbedtls_32_bit_fixes = {}
    if string.match(_ACTION, 'gmake.*') then
      table.insert(mbedtls_32_bit_fixes, '-mpclmul')
      table.insert(mbedtls_32_bit_fixes, '-msse2')
      table.insert(mbedtls_32_bit_fixes, '-maes')
    end

    cmake_build('mbedtls', true, mbedtls_common_defs, mbedtls_32_bit_fixes)
  end

  if _OPTIONS["64-build"] then
    cmake_build('mbedtls', false, mbedtls_common_defs)
  end
end

-- ##################################################
-- BUILD curl
-- ##################################################

if _OPTIONS["build-curl"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('curl')

  -- set defs
  local curl_common_defs = {
    "BUILD_CURL_EXE=OFF",
    "BUILD_STATIC_CURL=OFF", -- "Build curl executable with static libcurl"

    "BUILD_SHARED_LIBS=OFF",
    "BUILD_STATIC_LIBS=ON",
    "BUILD_MISC_DOCS=OFF",
    "BUILD_TESTING=OFF",
    "BUILD_LIBCURL_DOCS=OFF",
    "ENABLE_CURL_MANUAL=OFF",

    "CURL_USE_OPENSSL=OFF",
    "CURL_ZLIB=ON",

    "CURL_USE_MBEDTLS=ON",
    -- "CURL_USE_SCHANNEL=ON",
    "CURL_CA_FALLBACK=ON",

    -- fix building on Arch Linux
    "CURL_USE_LIBSSH2=OFF",
    "CURL_USE_LIBPSL=OFF",
    "USE_LIBIDN2=OFF",
    "CURL_DISABLE_LDAP=ON",
  }

  if os.target() == 'windows' and string.match(_ACTION, 'vs.+') then
    table.insert(curl_common_defs, "CURL_STATIC_CRT=ON")
    table.insert(curl_common_defs, "ENABLE_UNICODE=ON")
  end

  -- build
  if _OPTIONS["32-build"] then
    cmake_build('curl', true, merge_list(curl_common_defs, merge_list(wild_zlib_32, {
      'MBEDTLS_INCLUDE_DIRS="' .. path.join(deps_action_dir, 'mbedtls', 'install32', 'include') .. '"',
      'MBEDTLS_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install32', 'lib', mbedtls_name) .. '"',
      'MBEDCRYPTO_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install32', 'lib', mbedcrypto_name) .. '"',
      'MBEDX509_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install32', 'lib', mbedx509_name) .. '"',
    })))
  end

  if _OPTIONS["64-build"] then
    cmake_build('curl', false, merge_list(curl_common_defs, merge_list(wild_zlib_64, {
      'MBEDTLS_INCLUDE_DIRS="' .. path.join(deps_action_dir, 'mbedtls', 'install64', 'include') .. '"',
      'MBEDTLS_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install64', 'lib', mbedtls_name) .. '"',
      'MBEDCRYPTO_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install64', 'lib', mbedcrypto_name) .. '"',
      'MBEDX509_LIBRARY="' .. path.join(deps_action_dir, 'mbedtls', 'install64', 'lib', mbedx509_name) .. '"',
    })))
  end
end

-- ##################################################
-- BUILD protobuf
-- ##################################################

if _OPTIONS["build-protobuf"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('protobuf')

  -- set defs
  local protobuf_common_defs = {
    "ABSL_PROPAGATE_CXX_STD=ON",
    "protobuf_BUILD_PROTOBUF_BINARIES=ON",
    "protobuf_BUILD_PROTOC_BINARIES=ON",
    "protobuf_BUILD_LIBPROTOC=OFF",
    "protobuf_BUILD_LIBUPB=OFF",
    "protobuf_BUILD_TESTS=OFF",
    "protobuf_BUILD_EXAMPLES=OFF",
    "protobuf_DISABLE_RTTI=ON",
    "protobuf_BUILD_CONFORMANCE=OFF",
    "protobuf_BUILD_SHARED_LIBS=OFF",
    "protobuf_WITH_ZLIB=ON",
  }

  if os.target() == 'windows' and string.match(_ACTION, 'gmake.*') then
    table.insert(protobuf_common_defs, 'protobuf_MSVC_STATIC_RUNTIME=ON')
  end

  -- build
  if _OPTIONS["32-build"] then
    cmake_build('protobuf', true, merge_list(protobuf_common_defs, wild_zlib_32))
  end

  if _OPTIONS["64-build"] then
    cmake_build('protobuf', false, merge_list(protobuf_common_defs, wild_zlib_64))
  end
end

-- ##################################################
-- BUILD ingame_overlay
-- ##################################################

if _OPTIONS["build-ingame_overlay"] or _OPTIONS["all-build"] then
  -- copy dir
  cmake_copy('ingame_overlay')

  -- fixes 32-bit compilation of DX12
  local ingame_overlay_imcfg_file = path.join(deps_action_dir, 'ingame_overlay', 'imconfig.imcfg')
  if not io.writefile(ingame_overlay_imcfg_file, [[
        #pragma once
        #define ImTextureID ImU64
    ]]) then
    error('Failed to create ImGui config file for overlay: "' .. ingame_overlay_imcfg_file .. '"')
  end

  -- set defs
  local ingame_overlay_common_defs = {
    'IMGUI_USER_CONFIG="' .. ingame_overlay_imcfg_file:gsub('\\', '/') .. '"', -- ensure we use '/' because this lib doesn't handle it well
    'INGAMEOVERLAY_USE_SYSTEM_LIBRARIES=OFF',
    'INGAMEOVERLAY_USE_SPDLOG=OFF',
    'INGAMEOVERLAY_BUILD_TESTS=OFF',
  }

  -- fix missing standard include/header file for gcc/clang
  local ingame_overlay_cxx_fixes = {}
  if string.match(_ACTION, 'gmake.*') then
    -- MinGW fixes
    if os.target() == 'windows' then
      -- MinGW doesn't define _M_AMD64 or _M_IX86, which makes SystemDetector.h fail to recognize os
      -- MinGW throws this error: Filesystem.cpp:139:38: error: no matching function for call to 'stat::stat(const char*, stat*)
      table.insert(ingame_overlay_cxx_fixes, '-include sys/stat.h')
      -- MinGW throws this error: Library.cpp:77:26: error: invalid conversion from 'FARPROC' {aka 'long long int (*)()'} to 'void*' [-fpermissive]
      table.insert(ingame_overlay_cxx_fixes, '-fpermissive')
    end
  end

  -- build
  if _OPTIONS["32-build"] then
    cmake_build('ingame_overlay/deps/System', true, {
      'BUILD_SYSTEMLIB_TESTS=OFF',
    }, nil, ingame_overlay_cxx_fixes)
    cmake_build('ingame_overlay/deps/mini_detour', true, {
      'BUILD_MINIDETOUR_TESTS=OFF',
    })
    cmake_build('ingame_overlay', true, ingame_overlay_common_defs, nil, ingame_overlay_cxx_fixes)
  end

  if _OPTIONS["64-build"] then
    cmake_build('ingame_overlay/deps/System', false, {
      'BUILD_SYSTEMLIB_TESTS=OFF',
    }, nil, ingame_overlay_cxx_fixes)
    cmake_build('ingame_overlay/deps/mini_detour', false, {
      'BUILD_MINIDETOUR_TESTS=OFF',
    })
    cmake_build('ingame_overlay', false, ingame_overlay_common_defs, nil, ingame_overlay_cxx_fixes)
  end
end
