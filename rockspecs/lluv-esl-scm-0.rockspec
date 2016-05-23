package = "lluv-esl"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lua-lluv-esl/archive/master.zip",
  dir = "lua-lluv-esl-master",
}

description = {
  summary    = "FreeSWITCH ESL implementation for lluv library",
  homepage   = "https://github.com/moteus/lua-lluv-esl",
  license    = "MIT/X11",
  maintainer = "Alexey Melnichuk",
  detailed   = [[
  ]],
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "lluv",
  "eventemitter",
  "cjson",
  "luaexpat",
  "luuid",
  
}

build = {
  copy_directories = {'test'},

  type = "builtin",

  modules = {
    ["tpdu"          ] = "src/lua/tpdu.lua",
    ["tpdu.bit"      ] = "src/lua/tpdu/bit.lua",
    ["tpdu.bcd"      ] = "src/lua/tpdu/bcd.lua",
    ["tpdu.bit7"     ] = "src/lua/tpdu/bit7.lua",
    ["tpdu.utils"    ] = "src/lua/tpdu/utils.lua",
  }
}
