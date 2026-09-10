-- VimTeX compiles (latexmk, continuous) and shows the PDF in Okular. texlab
-- only provides LSP features (no build, no forward search), so two latexmk
-- runs never fight over the same files in build/.
--
-- Settings go in `init`, not `config`: VimTeX reads its g: variables when it
-- loads, and a `config` here would replace the one from LazyVim's tex extra
-- (which frees K for LSP hover).
return {
  {
    "lervag/vimtex",
    init = function()
      -- Viewer: Okular, with forward search
      vim.g.vimtex_view_general_viewer = "okular"
      vim.g.vimtex_view_general_options = "--unique file:@pdf\\#src:@line@tex"
      vim.g.vimtex_view_forward_search_on_start = false

      -- Build into build/ (~/.latexmkrc says the same and takes priority).
      -- The other latexmk options keep VimTeX's defaults.
      vim.g.vimtex_compiler_latexmk = { out_dir = "build" }

      -- Quickfix: open and focus on errors, skip box warnings
      vim.g.vimtex_quickfix_mode = 1
      vim.g.vimtex_quickfix_ignore_filters = { "Underfull", "Overfull" }

      -- No insert-mode mappings (LuaSnip handles snippets)
      vim.g.vimtex_imaps_enabled = 0
    end,
  },
}
