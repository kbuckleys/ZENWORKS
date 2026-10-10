-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- SPELLING. nvim's own checker ('spell', English from nvim's runtime — no
-- spell file to fetch), shown the way plato shows everything: view.lua
-- asks vim.spell.check() of each line on screen and paints a curl under
-- what it finds. In prose (markdown, plain text, a commit message) every
-- word is checked; in code only words in comments and strings.
--
--   Space k   spell checking on or off, for the window
--   z=        the suggestions, as a plato menu rather than nvim's list
--             (with "add to the dictionary" and "ignore")

local api = vim.api
local M = {}
local send = function() end

local proseTypes = { markdown = true, text = true, gitcommit = true, mail = true,
  rst = true, org = true, tex = true, plaintex = true, asciidoc = true, [""] = true }
function M.prose(buf) return proseTypes[vim.bo[buf].filetype] == true end

function M.toggle()
  vim.wo.spell = not vim.wo.spell
  vim.notify(vim.wo.spell and "Spell check on (z= suggests)" or "Spell check off")
end

-- the word under the cursor, put right
function M.use(word)
  vim.cmd('normal! "_ciw' .. word)
  vim.cmd("stopinsert")
end
function M.add(word, good)
  vim.cmd((good and "spellgood " or "spellgood! ") .. vim.fn.fnameescape(word))
  require("plato.view").schedule(true)
end

function M.suggest()
  local word = vim.fn.expand("<cword>")
  if word == "" then return end
  local list = vim.fn.spellsuggest(word, 12)
  send({ event = "spell", word = word, items = list })
end

function M.setup(sendFn)
  send = sendFn
  vim.o.spelllang = "en"
  -- words added go beside plato's state, not into a dictionary of the
  -- terminal nvim's
  vim.o.spellfile = vim.fn.stdpath("data") .. "/spell/en.utf-8.add"
  vim.fn.mkdir(vim.fn.stdpath("data") .. "/spell", "p")
  vim.keymap.set("n", "z=", M.suggest, { desc = "Spelling suggestions" })
end

return M
