-- Syntax highlighting via Treesitter.
-- Note: nvim-treesitter's "main" branch is a rewrite that only handles
-- parser install; highlighting/indent/folding are enabled via Neovim's
-- native vim.treesitter API, wired up below.
-- Parsers to install (treesitter language names).
local parsers = {
  "bash",
  "c",
  "cpp",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "vim",
  "vimdoc",
  "yaml",
}

-- Filetypes to attach treesitter to (differs from parser names for a few:
-- shell scripts are filetype "sh", vim help pages are filetype "help").
local filetypes = {
  "sh",
  "c",
  "cpp",
  "javascript",
  "json",
  "lua",
  "markdown",
  "python",
  "query",
  "vim",
  "help",
  "yaml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install(parsers)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = filetypes,
        callback = function()
          vim.treesitter.start()
          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },
}
