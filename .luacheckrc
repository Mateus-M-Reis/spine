std = "luajit"
max_line_length = false
globals = { "lovr", "utf8" }
ignore = {
  "212", -- unused argument
  "213", -- unused loop variable
  "311", -- initial value assigned but overwritten
  "411", -- variable previously defined in another branch
  "412", -- variable shadows function argument
  "421", -- variable shadows outer variable
  "432", -- upvalue shadows argument
  "542", -- empty branch (documented no-op)
  "122", -- math library fallback writes (LuaJIT compatibility)
  "631", -- long lines are allowed in this codebase
}
