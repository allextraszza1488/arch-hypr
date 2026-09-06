-- Default Neovim shortcuts/commands (:wq, :vsplit, gc/gcc comment toggling,
-- etc.) are kept as-is otherwise.

-- :terminal traps focus in terminal-mode until you explicitly leave with
-- Ctrl-\ Ctrl-N -- easy to not know, feels like the terminal "won't let go".
-- Plain Esc now leaves terminal-mode and drops you into normal mode on the
-- terminal buffer, matching every other mode in Vim.
-- Trade-off: any program running inside the terminal that itself listens
-- for a bare Escape key (e.g. another vim, a TUI with its own Esc bindings)
-- will see this Esc consumed by leaving terminal-mode instead of reaching
-- that program. Ctrl-\ Ctrl-N still works as the unambiguous fallback.
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Leave terminal-mode (was Ctrl-\\ Ctrl-N only)" })

-- Completion: with completeopt=noinsert (see options.lua), nothing gets
-- inserted until you confirm. Tab/Enter confirm the highlighted match when
-- the popup is visible; otherwise they behave completely normally (Enter
-- still runs nvim-autopairs' bracket-expand-on-Enter, Tab still inserts
-- a literal tab).
vim.keymap.set("i", "<Tab>", function()
  if vim.fn.pumvisible() == 1 then
    return "<C-y>"
  end
  return "<Tab>"
end, { expr = true })

vim.keymap.set("i", "<CR>", function()
  if vim.fn.pumvisible() == 1 then
    return "<C-y>"
  end
  local ok, npairs = pcall(require, "nvim-autopairs")
  if ok then
    return npairs.autopairs_cr()
  end
  return "<CR>"
end, { expr = true })

-- File tree: netrw (built-in, no plugin) in tree-style listing, docked to a
-- thin split at the bottom instead of the usual left sidebar.
vim.g.netrw_liststyle = 3
vim.g.netrw_banner = 0

local function toggle_file_tree()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "netrw" then
      vim.api.nvim_win_close(win, false)
      return
    end
  end
  -- Selecting a file in the tree should open it in the window you were just
  -- in, not replace the tree panel itself.
  local main_win = vim.api.nvim_get_current_win()
  vim.cmd("botright new")
  vim.cmd("resize 12")
  vim.cmd("edit .")
  vim.g.netrw_chgwin = vim.api.nvim_win_get_number(main_win)
end
vim.keymap.set("n", "<leader>e", toggle_file_tree, { desc = "Toggle file tree (bottom)" })

-- Shared by the makefile/debug-script runners below: edit the file (from a
-- template, if given) when it doesn't exist yet, otherwise run it in a
-- horizontal split pinned to the bottom of the tab at ~1/3 height.
local function run_or_create(filename, template)
  -- Resolve next to the file being edited, not against nvim's cwd. Opening
  -- nvim from a parent directory used to create the makefile up there
  -- instead of beside main.c.
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  local path = dir .. "/" .. filename

  if vim.fn.filereadable(path) == 0 then
    vim.cmd("vsplit " .. vim.fn.fnameescape(path))
    if template then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, template)
    end
  else
    vim.cmd("botright split")
    vim.api.nvim_win_set_height(0, math.floor(vim.o.lines / 3))
    -- cd first so relative paths inside the script resolve there too
    vim.cmd("terminal cd " .. vim.fn.shellescape(dir)
      .. " && sh " .. vim.fn.shellescape(filename))
    vim.cmd("startinsert")
  end
end

-- Name of the C source in the current buffer and the binary it builds.
-- Falls back to main.c when the buffer isn't a C file (e.g. you hit this
-- from netrw or from the makefile itself).
local function c_names()
  if vim.fn.expand("%:e") == "c" then
    return vim.fn.expand("%:t"), vim.fn.expand("%:t:r")
  end
  return "main.c", "main"
end

vim.keymap.set("n", "<leader>r", function()
  local src, exe = c_names()
  run_or_create("makefile", {
    ("gcc -Wall -Wextra -g %s -o %s && ./%s"):format(src, exe, exe),
  })
end, { desc = "Run makefile (bottom split), or create one from template if missing" })

vim.keymap.set("n", "<leader>g", function()
  local _, exe = c_names()
  run_or_create("script", { ("gdb ./%s"):format(exe) })
end, { desc = "Run debug script (bottom split), or create one from template if missing" })
