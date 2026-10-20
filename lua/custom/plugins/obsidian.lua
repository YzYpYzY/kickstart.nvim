-- Notes : le vault Obsidian ~/docs, édité depuis Neovim. Même dossier que
-- l'app Obsidian, les deux cohabitent sans migration.

local VAULT = vim.fn.expand '~/docs'

-- Noms de fichiers du vault : minuscules, tirets, sans accents
-- ("objectifs-presentation-cicd.md").
local function slug(title)
  local folded = title
  for from, to in pairs {
    ['[àâä]'] = 'a', ['[éèêë]'] = 'e', ['[îï]'] = 'i', ['[ôö]'] = 'o',
    ['[ùûü]'] = 'u', ['ç'] = 'c', ['œ'] = 'oe', ['æ'] = 'ae',
  } do
    folded = vim.fn.substitute(folded, from, to, 'g')
    folded = vim.fn.substitute(folded, vim.fn.toupper(from), to, 'g')
  end
  return require('obsidian.builtin').title_to_slug(folded)
end

-- Templater ne tourne que dans l'app. Les templates de _templates/ n'utilisent
-- que trois expressions, évaluées ici pour qu'ils servent tels quels :
--   <% tp.file.title %>                 titre saisi
--   <% tp.date.now("YYYY-MM-DD") %>     date du jour
--   <% await tp.system.suggester([...], [...], false, "Question") %>   choix
-- Toute autre expression est laissée telle quelle, avec un avertissement.
local function fill(text, title, done)
  text = text:gsub('<%%%s*tp%.file%.title%s*%%>', title)
  text = text:gsub('<%%%s*tp%.date%.now%("([^"]*)"%)%s*%%>', function(fmt)
    return require('obsidian.date').format(os.time(), fmt)
  end)

  -- Les suggesters, un par un : vim.ui.select rend la main par callback
  local s, e, values, question = text:find '<%%%s*await tp%.system%.suggester%((%b[]),%s*(%b[]).-"([^"]*)"%)%s*%%>'
  if not s then
    if text:find '<%%' then
      vim.notify('Expression Templater non gérée, laissée telle quelle', vim.log.levels.WARN)
    end
    return done(text)
  end
  local choices = {}
  for v in values:gmatch '"([^"]*)"' do
    table.insert(choices, v)
  end
  vim.ui.select(choices, { prompt = question }, function(choice)
    if not choice then
      return
    end
    fill(text:sub(1, s - 1) .. choice .. text:sub(e + 1), title, done)
  end)
end

-- Nouvelle note depuis un template, dans le dossier de la note ouverte (ou à
-- la racine du vault), comme le fait Templater dans l'app.
local function new_from_template()
  local templates = vim.fn.globpath(VAULT .. '/_templates', '*.md', false, true)
  vim.ui.select(templates, {
    prompt = 'Template',
    format_item = function(path)
      return vim.fn.fnamemodify(path, ':t:r')
    end,
  }, function(template)
    if not template then
      return
    end
    vim.ui.input({ prompt = 'Titre : ' }, function(title)
      if not title or vim.trim(title) == '' then
        return
      end
      local dir = vim.fn.expand '%:p:h'
      if not vim.startswith(dir, VAULT) then
        dir = VAULT
      end
      local path = dir .. '/' .. slug(title) .. '.md'
      if vim.uv.fs_stat(path) then
        vim.notify(path .. ' existe déjà', vim.log.levels.ERROR)
        return
      end
      local text = table.concat(vim.fn.readfile(template), '\n')
      fill(text, title, function(filled)
        vim.fn.writefile(vim.split(filled, '\n'), path)
        vim.cmd.edit(vim.fn.fnameescape(path))
      end)
    end)
  end)
end

return {
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*',
    ft = 'markdown',
    cmd = 'Obsidian',
    keys = {
      { '<leader>of', '<cmd>Obsidian quick_switch<cr>', desc = '[O]bsidian : trouver une note' },
      { '<leader>os', '<cmd>Obsidian search<cr>', desc = '[O]bsidian : chercher dans les notes' },
      { '<leader>ob', '<cmd>Obsidian backlinks<cr>', desc = '[O]bsidian : rétroliens' },
      { '<leader>on', new_from_template, desc = '[O]bsidian : nouvelle note depuis un template' },
      { '<leader>op', '<cmd>Obsidian paste_img<cr>', desc = '[O]bsidian : coller une image' },
    },
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false,
      workspaces = { { name = 'docs', path = VAULT } },

      -- Le frontmatter suit les conventions du vault (CLAUDE.md) : ne pas y
      -- ajouter id, aliases ni tags
      frontmatter = { enabled = false },
      note = { template = nil },
      note_id_func = slug,

      -- Templates Templater : gérés par <leader>on, pas par obsidian.nvim
      templates = { enabled = false },
      daily_notes = { enabled = false },

      attachments = { folder = '_attachments' },
      picker = { name = 'telescope.nvim' },

      -- Rendu laissé à render-markdown.nvim ; pas de compteurs en bas d'écran
      ui = { enable = false },
      footer = { enabled = false },
      statusline = { enabled = false },
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = 'markdown',
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      -- Sobre : titres sans fond coloré ni icône dans la marge
      heading = { sign = false, backgrounds = {} },
      code = { sign = false },
    },
  },
}
