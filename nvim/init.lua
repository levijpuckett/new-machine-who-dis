-- init.lua: your vimrc + LSP navigation, completion and diagnostics.
-- Needs Neovim 0.11+, git, and (for the pickers) fzf and ripgrep on your PATH.

---------------------------------------------------------------------------
-- 1. Your existing vimrc, unchanged (sets mapleader = "," before anything else)
---------------------------------------------------------------------------
for _, p in ipairs({ '~/.vimrc', '~/_vimrc' }) do
  if vim.fn.filereadable(vim.fn.expand(p)) == 1 then
    vim.cmd('source ' .. p)
    break
  end
end

-- Vim's regex C syntax marks { inside ( ) as an error, which breaks on compound literals
-- like f((type){ .x = 1 }). Only matters if tree-sitter highlighting isn't running.
vim.g.c_no_curly_error = 1

-- 24-bit colour (Windows Terminal supports it; colour schemes look wrong without it)
vim.o.termguicolors = true

-- Leave terminal mode with a double Esc (jk/kj would break typing in a shell)
vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]])

---------------------------------------------------------------------------
-- 2. Plugin manager (bootstraps itself on first launch)
---------------------------------------------------------------------------
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  -- Language servers: Mason installs them, lspconfig supplies sane defaults,
  -- mason-lspconfig enables whatever is installed.
  {
    'mason-org/mason-lspconfig.nvim',
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'neovim/nvim-lspconfig',
    },
    opts = { ensure_installed = { 'clangd', 'basedpyright', 'ruff' } },
  },

  -- Completion
  {
    'saghen/blink.cmp',
    version = '1.*',
    opts = {
      keymap = { preset = 'enter' }, -- Enter accepts, Tab/S-Tab or C-n/C-p to move
      signature = { enabled = true },
    },
  },

  -- Fuzzy finder: files, grep, symbols
  {
    'ibhagwan/fzf-lua',
    config = function()
      require('fzf-lua').setup({})
      require('fzf-lua').register_ui_select() -- preset picker, code actions etc. use fzf
    end,
  },

  -- Peek window for definitions/references (like CLion's quick definition)
  { 'dnlhc/glance.nvim', cmd = 'Glance', opts = {} },

  -- Smooth scrolling for C-d/C-u/C-f/C-b/C-e/C-y and zt/zz/zb
  {
    'karb94/neoscroll.nvim',
    opts = {
      duration_multiplier = 0.8, -- 1.0 = ~250 ms per half page; lower is snappier
      easing = 'quadratic',      -- quick start, gentle stop
    },
  },

  -- Colour scheme: JetBrains' "Dark" (New UI) palette, including clangd's semantic colours.
  -- Preview others live with :FzfLua colorschemes, then swap the plugin and name here.
  {
    'doums/dark.nvim',
    lazy = false,
    priority = 1000, -- load before everything else
    config = function() vim.cmd.colorscheme('dark') end,
  },

  -- Tree-sitter parsers for proper syntax highlighting.
  -- Needs the tree-sitter CLI (0.26.1+) and a C compiler on your PATH.
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').install({
        'c', 'cpp', 'python', 'cmake', 'bash', 'lua', 'vim', 'vimdoc', 'json', 'markdown',
      })
    end,
  },
})

-- Use tree-sitter highlighting wherever a parser exists (falls back to Vim syntax otherwise)
vim.api.nvim_create_autocmd('FileType', {
  callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
})

---------------------------------------------------------------------------
-- 3. Language server settings
---------------------------------------------------------------------------
local clangd_args = {
  'clangd',
  '--background-index',
  '--clang-tidy',
  '--header-insertion=never',
  -- Embedded: let clangd ask your cross-compiler for its system includes.
  -- Point this at your toolchain, e.g. '/opt/gcc-arm-none-eabi/bin/arm-none-eabi-*'
  -- '--query-driver=/path/to/toolchain/bin/arm-none-eabi-*',
}

-- Set by the :Preset command (section 5) to the active preset's build directory.
local clangd_db_dir = nil

vim.lsp.config('clangd', {
  -- A function rather than a list, so each (re)start picks up the current preset
  cmd = function(dispatchers)
    local args = vim.deepcopy(clangd_args)
    if clangd_db_dir then
      table.insert(args, '--compile-commands-dir=' .. clangd_db_dir)
    end
    return vim.lsp.rpc.start(args, dispatchers)
  end,
})

-- Enable explicitly so a clangd from your system/LLVM install also works, not just Mason's
vim.lsp.enable({ 'clangd', 'basedpyright', 'ruff' })

-- Warnings/errors inline (0.11 turned virtual text off by default)
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = 'rounded', source = true },
})

---------------------------------------------------------------------------
-- 4. Your ideavimrc mappings, ported. Buffer-local, so they only exist
--    where a language server is attached.
---------------------------------------------------------------------------
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local fzf = require('fzf-lua')

    map('<leader>e', vim.diagnostic.open_float, 'Show error description')
    map('<leader>s', vim.lsp.buf.definition, 'Go to declaration/definition')
    map('<leader>x', '<cmd>Glance definitions<CR>', 'Peek definition')
    map('<leader>R', vim.lsp.buf.rename, 'Rename')
    map('<leader>g', vim.lsp.buf.references, 'Find usages (into quickfix)')
    map('<leader>c', vim.lsp.buf.code_action, 'Code action / quick fix')

    -- Symbol search
    map('<leader>o', fzf.lsp_document_symbols, 'Symbols in file')
    map('<leader>O', fzf.lsp_live_workspace_symbols, 'Symbols in project')

    -- Fold with the language server's understanding of the code when it can
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method('textDocument/foldingRange') then
      vim.wo.foldmethod = 'expr'
      vim.wo.foldexpr = 'v:lua.vim.lsp.foldexpr()'
    end
  end,
})

-- These work everywhere, LSP or not
local map = vim.keymap.set
map('n', '<leader>a', '<C-o>', { desc = 'Back' })
map('n', '<leader>f', '<C-i>', { desc = 'Forward' })
map('n', '<leader>n', '<cmd>cnext<CR>', { desc = 'Next occurrence (quickfix)' })
map('n', '<leader>N', '<cmd>cprev<CR>', { desc = 'Previous occurrence (quickfix)' })
-- JetBrains double-shift: files by default, $ buffers, @ symbols in file, # symbols in project
map('n', '<leader><leader>', function() require('fzf-lua').global() end, { desc = 'Search everything' })
map('n', '<leader>?', function() require('fzf-lua').builtin() end, { desc = 'Search all pickers' })
map('n', '<leader>p', function() require('fzf-lua').files() end, { desc = 'Find file' })
map('n', '<leader>/', function() require('fzf-lua').live_grep() end, { desc = 'Grep project' })
map('n', '<leader>t', '<cmd>botright split | terminal<CR>', { desc = 'Terminal' })

---------------------------------------------------------------------------
-- 5. CMake presets, like CLion's profile dropdown.
--    :Preset (or ,P) picks a configure preset, runs `cmake --preset`, points
--    clangd at build/<preset>/compile_commands.json, makes ,b build it, and
--    restarts clangd. The choice is remembered per project.
---------------------------------------------------------------------------
local preset_file = vim.fn.stdpath('state') .. '/cmake-presets.json'

local function read_preset_state()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(preset_file), '\n'))
  end)
  return (ok and type(data) == 'table') and data or {}
end

local function current_preset()
  return read_preset_state()[vim.fn.getcwd()]
end

local function list_presets(kind)
  local res = vim.system({ 'cmake', '--list-presets=' .. kind }, { text = true }):wait()
  local names = {}
  for name in (res.stdout or ''):gmatch('\n%s+"([^"]+)"') do
    table.insert(names, name)
  end
  return names
end

local function restart_clangd()
  for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
    client:stop()
  end
  vim.defer_fn(function()
    vim.lsp.enable('clangd', false)
    vim.lsp.enable('clangd') -- re-attaches to open C/C++ buffers
  end, 500)
end

local function use_preset(name)
  vim.notify('Configuring preset ' .. name .. '...')
  vim.system({ 'cmake', '--preset', name, '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON' }, { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          vim.notify('cmake --preset ' .. name .. ' failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
          return
        end
        local dir = (res.stdout or ''):match('Build files have been written to: ([^\r\n]+)')
        if not dir then
          vim.notify('Could not find the build directory in cmake output', vim.log.levels.ERROR)
          return
        end

        clangd_db_dir = dir

        -- Build with the matching build preset if there is one, else the build dir
        local makeprg = vim.tbl_contains(list_presets('build'), name)
            and ('cmake --build --preset ' .. name)
            or ('cmake --build ' .. vim.fn.shellescape(dir))
        vim.o.makeprg = makeprg

        local state = read_preset_state()
        state[vim.fn.getcwd()] = { name = name, dir = dir, makeprg = makeprg }
        vim.fn.mkdir(vim.fn.fnamemodify(preset_file, ':h'), 'p')
        vim.fn.writefile({ vim.json.encode(state) }, preset_file)

        restart_clangd()
        vim.notify('Preset: ' .. name)
      end)
    end)
end

vim.api.nvim_create_user_command('Preset', function(opts)
  if opts.args ~= '' then return use_preset(opts.args) end
  local names = list_presets('configure')
  if #names == 0 then
    return vim.notify('No CMake presets found here', vim.log.levels.WARN)
  end
  local cur = current_preset()
  vim.ui.select(names, { prompt = 'CMake preset' .. (cur and (' (current: ' .. cur.name .. ')') or '') },
    function(choice) if choice then use_preset(choice) end end)
end, { nargs = '?', complete = function() return list_presets('configure') end })

map('n', '<leader>P', '<cmd>Preset<CR>', { desc = 'Choose CMake preset' })

-- Build: the command lives in 'makeprg' (set from the remembered preset, else build/).
local saved = current_preset()
if saved then
  vim.o.makeprg = saved.makeprg
  clangd_db_dir = saved.dir
elseif vim.fn.filereadable('CMakeLists.txt') == 1 then
  vim.o.makeprg = 'cmake --build build'
end

-- Only real GCC/Clang/linker diagnostics become quickfix entries; all other build output
-- (version banners, memory maps, timestamps that look like file:line) is ignored.
vim.o.errorformat = table.concat({
  '%f:%l:%c: fatal %trror: %m',
  '%f:%l:%c: %trror: %m',
  '%f:%l:%c: %tarning: %m',
  '%f:%l:%c: %tote: %m',
  -- Linker errors, optionally prefixed with the linker's own path ("/path/to/ld: "):
  --   file.c:74:(.text+0x1c): undefined reference to `foo'   (with debug info)
  --   file.c:(.text+0x1c): undefined reference to `foo'      (without)
  '%*[^ ] %f:%l:(%.%#): %m',
  '%*[^ ] %f:(%.%#): %m',
  '%f:%l:(%.%#): %m',
  '%f:(%.%#): %m',
  '%-G%.%#',
}, ',')

-- Runs in the background: the editor stays usable, there's no "Press ENTER" prompt and
-- no jumping to a file. Errors/warnings land in quickfix (walk them with ,n / ,N).
local last_build_output = {}

local function build(extra)
  local cmd = vim.o.makeprg .. (extra and (' ' .. extra) or '')
  vim.notify('Building: ' .. cmd)
  vim.system({ 'sh', '-c', cmd .. ' 2>&1' }, { text = true }, function(res)
    vim.schedule(function()
      last_build_output = vim.split(res.stdout or '', '\n', { trimempty = true })
      vim.fn.setqflist({}, ' ', { title = cmd, lines = last_build_output })

      local errors, warnings = 0, 0
      for _, item in ipairs(vim.fn.getqflist()) do
        if item.valid == 1 then
          if item.type:lower() == 'w' then
            warnings = warnings + 1
          elseif item.type:lower() == 'e' or item.type == '' then
            errors = errors + 1
          end
        end
      end

      if res.code == 0 then
        vim.notify(('Build OK (%d warning%s)'):format(warnings, warnings == 1 and '' or 's'))
        if warnings > 0 then vim.cmd('botright cwindow') else vim.cmd('cclose') end
      elseif errors > 0 then
        vim.notify(('Build FAILED: %d error(s), %d warning(s)'):format(errors, warnings), vim.log.levels.ERROR)
        vim.cmd('botright cwindow')
        vim.cmd('cfirst')
      else
        -- Failed without a recognisable error (CMake error, linker region overflow...): show it all.
        -- Any warnings are still in quickfix for afterwards.
        vim.notify('Build FAILED, see :BuildLog', vim.log.levels.ERROR)
        vim.cmd('BuildLog')
      end
    end)
  end)
end

-- Full output of the last build (memory usage summary etc.) in a scratch split
vim.api.nvim_create_user_command('BuildLog', function()
  vim.cmd('botright new')
  vim.bo.buftype, vim.bo.bufhidden, vim.bo.swapfile = 'nofile', 'wipe', false
  vim.api.nvim_buf_set_lines(0, 0, -1, false, last_build_output)
  vim.bo.modifiable = false
  vim.cmd('normal! G')
end, {})

map('n', '<leader>b', function() build() end, { desc = 'Build' })
map('n', '<leader>B', function()
  build(vim.o.makeprg:match('^cmake') and '--clean-first' or 'clean all')
end, { desc = 'Rebuild' })
map('n', '<leader>l', '<cmd>BuildLog<CR>', { desc = 'Show last build output' })

-- Quickfix list: ,q opens/closes it from anywhere; q closes it from inside
map('n', '<leader>q', function()
  if vim.fn.getqflist({ winid = 0 }).winid ~= 0 then vim.cmd('cclose') else vim.cmd('botright copen') end
end, { desc = 'Toggle quickfix list' })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function(ev) vim.keymap.set('n', 'q', '<cmd>cclose<CR>', { buffer = ev.buf }) end,
})

-- Serial monitor in a split. Swap in your tool and port (tio, picocom, minicom...).
-- map('n', '<leader>m', '<cmd>vsplit | terminal tio /dev/ttyUSB0<CR>', { desc = 'Serial monitor' })

-- Not ported yet: <leader>r (Run) and <leader>d (Debug) are project/target specific.
-- [[ and ]] already jump between C functions natively (when the { is in column 0).
