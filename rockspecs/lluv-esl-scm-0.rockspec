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
  "lua-cjson",
  "luaexpat",
  "luuid",
  
}

build = {
  copy_directories = {'test'},

  type = "builtin",

  modules = {
    ["lluv.esl"           ] = "src/lluv/esl.lua",
    ["lluv.esl.error"     ] = "src/lluv/esl/error.lua",
    ["lluv.esl.utils"     ] = "src/lluv/esl/utils.lua",
  }
}
