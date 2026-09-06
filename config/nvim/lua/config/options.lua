-- Everything else stays vanilla Neovim (:wq, :vsplit, etc. all behave as normal).

-- Leader key for custom keymaps (see keymaps.lua) — must be set before any
-- <leader> mapping is defined.
vim.g.mapleader = " "

-- Show line numbers, relative to the cursor (so `5j`/`3dd`-style counts are
-- readable at a glance instead of guessed).
vim.opt.number = true
vim.opt.relativenumber = true

-- LSP completion: show the menu of matches as you type, but never insert
-- anything into the buffer until you actually confirm an item (Tab/Enter,
-- wired up in keymaps.lua). Without `noinsert`, Neovim provisionally shoves
-- the top match into the buffer as a preview — that's what was auto-filling
-- `#include<` with garbage and causing doubled Tab/Enter/Backspace.
vim.opt.completeopt = "menuone,noinsert,popup"

-- True-color highlighting (this terminal supports it) so the colorscheme's
-- full palette renders instead of a squashed 256-color approximation.
vim.opt.termguicolors = true

-- h/l, arrow keys, and backspace/space all wrap to the previous/next line
-- when the cursor is at the first/last character of a line (normal, visual
-- and insert mode).
vim.opt.whichwrap = "b,s,h,l,<,>,[,]"

-- Let visual block (Ctrl-V) selection move freely up/down/left/right,
-- including past the end of shorter lines, so you can box-select real
-- rectangles of text.
vim.opt.virtualedit = "block"

-- Tab key inserts 4 spaces instead of a literal tab character. tabstop
-- still controls how existing literal tabs (e.g. from files written
-- elsewhere) are displayed width-wise.
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4

-- Show whitespace: a small arrow for tabs, a dot for regular spaces, a dot
-- for trailing spaces, and a subtle mark at end-of-line.
vim.opt.list = true
vim.opt.listchars = "tab:▸ ,space:·,trail:·,eol:¬"

-- Safety nets: recover from crashes/accidental data loss instead of
-- trusting a single in-memory buffer.
vim.opt.undofile = true                          -- persistent undo across sessions
vim.opt.undodir = vim.fn.stdpath("state") .. "/undo"
vim.opt.backup = true                             -- keep a backup~ file on write
vim.opt.backupdir = vim.fn.stdpath("state") .. "/backup"
vim.opt.swapfile = true                           -- swapfile for crash recovery
vim.opt.directory = vim.fn.stdpath("state") .. "/swap"
vim.fn.mkdir(vim.fn.stdpath("state") .. "/undo", "p")
vim.fn.mkdir(vim.fn.stdpath("state") .. "/backup", "p")

-- 2. Force your exact Alpenflage colors over it
local autocmd = vim.api.nvim_create_autocmd
autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    -- Main editor background and text (Khaki)
    vim.api.nvim_set_hl(0, "Normal", { bg = "#1D2021", fg = "#C1A376" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#1D2021", fg = "#C1A376" })
    
    -- Inactive line numbers (Alpine Green)
    vim.api.nvim_set_hl(0, "LineNr", { fg = "#3A4D39" })         
    
    -- Active line number (Alpen Red)
    vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#9D2B32", bold = true }) 
    
    -- Coding Keywords and Statements (Alpen Red)
    vim.api.nvim_set_hl(0, "Statement", { fg = "#9D2B32", bold = true })      
    vim.api.nvim_set_hl(0, "Keyword", { fg = "#9D2B32" })
    
    -- Strings and Functions (Khaki / Tan)
    vim.api.nvim_set_hl(0, "String", { fg = "#D5BA8E" })
    vim.api.nvim_set_hl(0, "Function", { fg = "#C1A376" })       
    
    -- Comments (Muted Slate Blue)
    vim.api.nvim_set_hl(0, "Comment", { fg = "#5B7A91", italic = true }) 
    
    -- Visual selection background (Dark Green)
    vim.api.nvim_set_hl(0, "Visual", { bg = "#3A4D39" })         
    
    -- Keep LazyVim UI background solid
    vim.api.nvim_set_hl(0, "LazyNormal", { bg = "#1D2021" })
  end,
})

-- Trigger it once manually to apply immediately on startup
-- (a verbatim duplicate of the block above used to sit here: same 11
--  highlight calls, silently overwriting itself with identical values)

vim.cmd("colorscheme habamax")



-- ------------------------------------------------------- FIND FILES BY NAME
-- Does   let you jump to a file when you only know its NAME, not its path.
-- Links  <- the hyprland.lua comments name bare files ("scripts/toggle-look.sh",
--           "look-state.lua"). This is what makes those names clickable.
-- Watch  "**" makes :find and gf search the whole tree under the cwd. In a huge
--        repo that makes tab-completion slow -- fine here, this config tree is
--        small, but that is the tradeoff if it ever feels sluggish.
--
--   gf              cursor on a filename -> open it
--   gF              same, but jump to the line number after it too
--   CTRL-W f        open it in a split instead
--   CTRL-O          jump back where you came from
--   :find <name>    Tab-completes across the whole tree, no path needed
--   :sfind / :vert sfind   same, into a horizontal / vertical split
vim.opt.path:append("**")

-- Lets gf resolve a bare "options" as "options.lua" -- Lua require() paths and
-- the [[wiki-style]] names in notes drop the extension, so without this gf
-- reports "file not found" on a file that is right there.
vim.opt.suffixesadd:append({ ".lua", ".sh", ".md", ".txt", ".conf" })
