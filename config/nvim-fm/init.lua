-- Standalone Neovim entry point for a ranger/vifm-style file manager.
-- Launched via scripts/filemanager-nvim.sh, which sets NVIM_FM_START_DIR
-- and calls `nvim -u this-file` with NO positional file argument.
--
-- This does NOT use netrw. Earlier versions did, but netrw's own <CR>
-- handling (browse into a dir / open a file) isn't something you can cleanly
-- hook into from the outside -- there's no clean "user just selected X"
-- callback, just internal functions never meant to be called externally.
-- So instead: a plain scratch buffer we fill ourselves with a directory
-- listing, and OUR OWN <CR> handler that knows exactly what was selected.
-- Less code reuse, much more control -- worth it for the behavior wanted
-- here (auto-cd the terminal, echo the path, shift focus into a preview
-- window on file-open).
--
-- Layout:
--   +-------------------+-------------------+
--   |  tree (left)      |  preview (right,  |
--   |                   |  blank until you  |
--   |                   |  open a file)     |
--   +-------------------+-------------------+
--   |         terminal (bottom, full width)         |
--   +-------------------------------------------------+
--
-- Behavior:
--   <CR> on ".."     -> go up a directory
--   <CR> on a dir/   -> descend into it
--     Both of the above: refresh the tree listing, AND send `cd <path>`
--     followed by `echo <path>` to the terminal's shell -- so the terminal
--     always sits in whatever directory you're currently browsing, and you
--     get a visible confirmation line each time you move.
--   <CR> on a file   -> open it in a SEPARATE kitty window running plain
--     nvim (the normal ~/.config/nvim config). "The editor" means its own
--     window, not a third pane inside the file manager.
--   p    on a file   -> the older behaviour: load it into the preview pane
--     on the right and move focus there, for a look without a new window.
--     Exception (both keys): image files (png/jpg/jpeg/gif/webp/bmp) can't be displayed
--     as text, and Neovim's built-in terminal emulator can't run kitty's
--     image kitten either -- tested directly: `kitty +kitten icat` inside
--     a nested :terminal buffer errors with "Terminal does not support
--     reporting screen sizes in pixels", because nvim's terminal layer
--     doesn't implement the query icat needs. That's a real limitation of
--     nvim's terminal emulation, not something fixable from in here without
--     adding the image.nvim plugin (which draws directly to the real
--     terminal, bypassing the nested-terminal problem entirely -- an option
--     if inline preview turns out to matter more than staying plugin-free).
--     For now: images open in a genuinely separate, real kitty window
--     (its own pty, so icat's query actually gets answered), spawned
--     alongside rather than replacing the preview pane.

vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]])

local IMAGE_EXTS = {
  png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true,
}

local start_dir = vim.env.NVIM_FM_START_DIR
if start_dir == nil or start_dir == "" then
  start_dir = vim.fn.getcwd()
end
start_dir = vim.fn.fnamemodify(start_dir, ":p"):gsub("/$", "")

-- All the mutable state this file manager needs, in one place: current
-- directory being browsed, the window/buffer ids created at startup, and
-- the terminal job's channel id (needed to send it "cd"/"echo" commands).
local M = {
  dir = start_dir,
  tree_buf = nil,
  tree_win = nil,
  preview_win = nil,
  term_job_id = nil,
}

-- Rebuilds the tree buffer's lines from M.dir. ".." first, then
-- directories (name + "/"), then files, each alphabetically. The "/"
-- suffix is how <CR> tells a directory line from a file line later --
-- deliberately not using any icon/plugin for this, just a plain character.
local function refresh_tree()
  local entries = vim.fn.readdir(M.dir)
  local dirs, files = {}, {}
  for _, name in ipairs(entries) do
    if vim.fn.isdirectory(M.dir .. "/" .. name) == 1 then
      table.insert(dirs, name)
    else
      table.insert(files, name)
    end
  end
  table.sort(dirs)
  table.sort(files)

  local lines = { ".." }
  for _, d in ipairs(dirs) do
    table.insert(lines, d .. "/")
  end
  for _, f in ipairs(files) do
    table.insert(lines, f)
  end

  vim.bo[M.tree_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.tree_buf, 0, -1, false, lines)
  vim.bo[M.tree_buf].modifiable = false
  -- Buffer name shows the current directory in the statusline/title.
  pcall(vim.api.nvim_buf_set_name, M.tree_buf, "FileTree: " .. M.dir)
  -- Cursor back to the top (past the dir change, line 1 is always "..").
  pcall(vim.api.nvim_win_set_cursor, M.tree_win, { 1, 0 })
end

-- Tells the terminal's actual shell to follow along: cd into the new
-- directory, then echo it, so there's always a visible "you are here" line
-- in the terminal even if you never look at the tree pane again.
local function sync_terminal_to_dir()
  if not M.term_job_id then
    return
  end
  local cmd = "cd " .. vim.fn.shellescape(M.dir) .. "; echo " .. vim.fn.shellescape(M.dir) .. "\n"
  vim.fn.chansend(M.term_job_id, cmd)
end

-- Opens `path` in the preview window and moves focus there, landing in
-- normal mode -- exactly like opening any file normally, just targeting a
-- specific window instead of the current one.
local function open_in_preview(path)
  vim.api.nvim_set_current_win(M.preview_win)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.cmd("stopinsert")
end

-- Images: can't be shown as text, and can't use icat inside nvim's own
-- :terminal (verified: kitty's icat kitten needs a real controlling tty to
-- query screen size, and nvim's built-in terminal emulator doesn't answer
-- that query). Was briefly a nested `kitty -e kitty +kitten icat` popup
-- (confirmed working via screenshot), swapped for imv instead: a real
-- Wayland-native image viewer with actual controls (zoom/pan/rotate/flip/
-- next-prev), not just a fixed-function display-and-exit kitten.
--
-- Class confirmed live via hyprctl clients -j: imv really does report
-- class "imv", matching the window_rule in hyprland.lua exactly.
local function open_image_popup(path)
  vim.fn.jobstart({ "imv", path }, { detach = true })
end

-- Regular files: a genuinely separate editor window, not the preview pane.
-- Same reasoning as images -- "open this file" should hand you a real window
-- containing nothing but the editor, rather than a third pane wedged into the
-- file manager's own layout. detach = true so the editor outlives the file
-- manager: closing the browser must not kill a file you're still editing.
--
-- --class nvim-editor exists purely so hyprland.lua can match it. Without a
-- distinct class it comes up as plain "kitty" and lands BEHIND the file
-- manager, which is float+pin (an elevated layer a normal window can't reach)
-- -- exactly the bug imv hit before its own rule was added.
--
-- Plain `nvim`, no -u: this instance gets the NORMAL ~/.config/nvim config,
-- not nvim-fm/init.lua. That is the point -- you asked for the editor, not
-- another file manager.
local function open_in_editor(path)
  vim.fn.jobstart(
    { "kitty", "--class", "nvim-editor", "-e", "nvim", path },
    { detach = true }
  )
end

-- The <CR> handler: figure out what line the cursor is on, decide whether
-- it's ".." / a directory / a file, and act accordingly. This is the one
-- function that replaces everything netrw used to do internally and
-- invisibly -- now it's all here, readable top to bottom.
local function on_select(open_file)
  local lnum = vim.api.nvim_win_get_cursor(M.tree_win)[1]
  local name = vim.api.nvim_buf_get_lines(M.tree_buf, lnum - 1, lnum, false)[1]
  if not name or name == "" then
    return
  end

  if name == ".." then
    M.dir = vim.fn.fnamemodify(M.dir, ":h")
    refresh_tree()
    sync_terminal_to_dir()
    return
  end

  if name:sub(-1) == "/" then
    M.dir = M.dir .. "/" .. name:sub(1, -2)
    refresh_tree()
    sync_terminal_to_dir()
    return
  end

  -- Not a directory: a file. Full path, then branch on whether it's an
  -- image (see open_image_popup's comment for why images are special).
  local path = M.dir .. "/" .. name
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  if IMAGE_EXTS[ext] then
    open_image_popup(path)
  else
    open_file(path)
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- Step 1: split off the bottom terminal FIRST, full width, from the
    -- single starting window. Order matters here -- doing this first means
    -- the terminal spans the whole width; if we split left/right before
    -- this, the terminal would only span whichever side we did it from.
    vim.cmd("botright new")
    vim.api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.25))
    -- jobstart(..., {term=true}) is the current API; the older termopen()
    -- is deprecated (confirmed: doc/deprecated.txt says to use this).
    M.term_job_id = vim.fn.jobstart({ "fish" }, { term = true, cwd = M.dir })

    -- Step 2: back up to the remaining top area (still one single window
    -- at this point, spanning the full width above the terminal), and
    -- split THAT into tree (left) + preview (right).
    vim.cmd("wincmd k")
    M.tree_win = vim.api.nvim_get_current_win()
    M.tree_buf = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
    vim.bo[M.tree_buf].buftype = "nofile"
    vim.bo[M.tree_buf].bufhidden = "hide"
    vim.bo[M.tree_buf].swapfile = false
    vim.api.nvim_win_set_buf(M.tree_win, M.tree_buf)

    vim.cmd("vertical rightbelow new")
    M.preview_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(M.preview_win, math.floor(vim.o.columns * 0.5))
    -- Preview starts genuinely blank -- an empty scratch buffer, nothing
    -- opened until a file is actually selected in the tree.
    vim.bo[vim.api.nvim_get_current_buf()].buftype = "nofile"

    -- <CR> only makes sense in the tree window, so the keymap is
    -- buffer-local to M.tree_buf, not global.
    -- <CR> opens files in their own window; "p" keeps the old in-pane
    -- behaviour for a quick peek without spawning anything. Directories
    -- behave identically under both.
    vim.keymap.set("n", "<CR>", function() on_select(open_in_editor) end,
      { buffer = M.tree_buf })
    vim.keymap.set("n", "p", function() on_select(open_in_preview) end,
      { buffer = M.tree_buf })

    refresh_tree()
    vim.api.nvim_set_current_win(M.tree_win)
  end,
})
