return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "mason-org/mason.nvim",
      "jay-babu/mason-nvim-dap.nvim",
    },
    opts = function()
      return {
        -- This ensures Mason installs codelldb on Arch as well
        ensure_installed = { "codelldb" },
      }
    end,
    config = function()
      local dap = require("dap")

      -- Path to Mason-installed codelldb
      local codelldb_path = vim.fn.stdpath("data") .. "/mason/bin/codelldb"

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = codelldb_path,
          args = { "--port", "${port}" },
        },
      }

      dap.configurations.c = {
        {
          name = "Launch C program",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
      }

      -- Reuse C config for C++
      dap.configurations.cpp = dap.configurations.c
    end,
  },
}
