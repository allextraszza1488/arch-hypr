-- Per-filetype overrides. The global default is 4 spaces (options.lua),
-- which is right for C but not for everything.

-- Lua convention is 2 spaces, and lua_ls/stylua reformat to 2 regardless —
-- so matching it here keeps hand-written lines consistent with formatted
-- ones instead of fighting the formatter on every save.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "lua" },
  callback = function()
    vim.bo.tabstop = 2
    vim.bo.shiftwidth = 2
    vim.bo.softtabstop = 2
    vim.bo.expandtab = true
  end,
})

-- ~/.config/hypr/hyprland.lua has no .lua-detecting shebang and lives
-- outside any Lua project, but it is Lua — make sure it is treated as such
-- even if opened via a symlink.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*/hypr/*.lua" },
  callback = function() vim.bo.filetype = "lua" end,
})

-- Briefly highlight whatever was just yanked, so it is obvious what got
-- copied — especially with block selections.
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})
