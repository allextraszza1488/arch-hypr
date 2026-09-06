-- LSP: clangd for C/C++, using Neovim's built-in LSP client + completion
-- (no completion-engine plugin needed on 0.11+).
return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    config = function()
      vim.lsp.config("clangd", {
        cmd = { "clangd", "--background-index" },
      })
      vim.lsp.enable("clangd")

      -- Lua: for the nvim config itself and for ~/.config/hypr/hyprland.lua.
      -- Hyprland ships LuaLS type definitions in /usr/share/hypr/stubs, so
      -- pointing the server at them gives completion and inline docs for the
      -- whole hl.* API — every dispatcher, every config field, every bind
      -- flag. Beats grepping the stubs by hand.
      vim.lsp.config("lua_ls", {
        cmd = { "lua-language-server" },
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            workspace = {
              checkThirdParty = false,
              library = {
                vim.env.VIMRUNTIME,
                "/usr/share/hypr/stubs",
              },
            },
            -- `vim` is injected by Neovim, `hl` by Hyprland; neither is
            -- declared anywhere, so the server would flag them as undefined.
            diagnostics = { globals = { "vim", "hl" } },
            telemetry = { enable = false },
          },
        },
      })
      vim.lsp.enable("lua_ls")

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
          end

          vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = args.buf, desc = "Go to definition" })

          -- Diagnostics (warnings/errors) are shown automatically as
          -- underline + virtual text, but these let you actually navigate
          -- them instead of just staring at the line.
          local buf = args.buf
          vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { buffer = buf, desc = "Show diagnostic under cursor" })
          vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, { buffer = buf, desc = "Next diagnostic" })
          vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, { buffer = buf, desc = "Previous diagnostic" })
          vim.keymap.set("n", "<leader>D", function()
            vim.diagnostic.setqflist()
            vim.cmd("copen")
          end, { buffer = buf, desc = "List all diagnostics (quickfix)" })

          -- Format the whole file (indentation, spacing, brace style) via
          -- clangd, which shells out to clang-format under the hood.
          if client and client:supports_method("textDocument/formatting") then
            vim.keymap.set("n", "<leader>f", function()
              vim.lsp.buf.format({ async = false })
            end, { buffer = buf, desc = "Format file" })
          end
        end,
      })
    end,
  },
}
