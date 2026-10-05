-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- SAVING A FILE YOU DO NOT OWN. /etc/hosts, a file under /usr: :w used to
-- fail with E212 and leave you with an editor that could not finish the job.
-- Now a buffer whose file this user cannot write is written by plato
-- instead (a BufWriteCmd of its own): the card in the corner asks first,
-- and "Save as root" writes the text to a temporary file and has pkexec
-- copy it over the real one — sudoedit's way round, with the desktop's
-- polkit agent asking for the password. `cat >` into the file, not a move:
-- the file keeps its owner, its mode and its inode.
--
-- Such a buffer is NOT 'readonly' here, though nvim would make it so:
-- 'readonly' stops :w before a BufWriteCmd is ever asked. The status line
-- shows a shield in its place (status.lua's `root`).
--
-- AND :w NEVER REACHES nvim's WRITE. Before any autocommand, nvim looks at
-- the file's permissions itself and refuses with E505 ("is read-only"). So
-- :w, :wq and :x typed for such a buffer are taken on the command line, as
-- a :w with no file name is (editing.lua), and come here instead; Space w
-- comes through M.save. The BufWriteCmd is for the rest — :w! and :update.

local api = vim.api
local M = {}

-- can this user write it — or, for a file that is not there yet, make it?
function M.writable(path)
  if vim.uv.fs_stat(path) then return vim.uv.fs_access(path, "W") == true end
  local dir = vim.fs.dirname(path)
  while dir and not vim.uv.fs_stat(dir) do
    local up = vim.fs.dirname(dir)
    if up == dir then break end
    dir = up
  end
  return dir ~= nil and vim.uv.fs_access(dir, "W") == true
end

local function tidy(path) return vim.fn.fnamemodify(path, ":~") end

-- the buffer's text, as nvim would write it ('fileformat', 'eol', the
-- encoding), into a file of this user's; then pkexec copies it over
local function write(buf, target, quit)
  local tmp = vim.fn.tempname()
  -- what :w would have done first: trimming, formatting (editing.lua)
  pcall(api.nvim_exec_autocmds, "BufWritePre", { buffer = buf, modeline = false })
  local ok, err = pcall(api.nvim_buf_call, buf, function()
    vim.cmd("noautocmd keepalt silent write! " .. vim.fn.fnameescape(tmp))
  end)
  if not ok then
    vim.notify("Could not write " .. tidy(target) .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.system({ "pkexec", "sh", "-c", 'cat -- "$1" > "$2"', "sh", tmp, target }, { text = true },
    vim.schedule_wrap(function(r)
      os.remove(tmp)
      if r.code == 0 then
        if api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modified = false
          -- read back, so nvim's idea of the file's time is the new one and
          -- the change watch (disk.lua) does not take this write for someone
          -- else's
          api.nvim_buf_call(buf, function() vim.cmd("silent! checktime") end)
          pcall(api.nvim_exec_autocmds, "BufWritePost", { buffer = buf, modeline = false })
        end
        vim.notify(tidy(target) .. " written as root")
        if quit then vim.cmd("quit") end
      elseif r.code == 126 then
        vim.notify("Not saved: the password was not given", vim.log.levels.WARN)
      elseif r.code == 127 then
        vim.notify("Not saved: not allowed to act as root", vim.log.levels.ERROR)
      else
        vim.notify("Not saved: " .. vim.trim(r.stderr or ("pkexec said " .. r.code)),
          vim.log.levels.ERROR)
      end
    end))
end

local asking = {}
local function onWrite(ev)
  local buf = ev.buf
  local target = vim.fn.fnamemodify(ev.match, ":p")
  local own = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":p")
  -- :w somewhere else, somewhere this user CAN write: an ordinary write
  if target ~= own or M.writable(target) then
    api.nvim_buf_call(buf, function()
      vim.cmd("noautocmd keepalt " .. (vim.v.cmdbang == 1 and "write! " or "write ")
        .. vim.fn.fnameescape(target))
    end)
    if target == own then vim.bo[buf].modified = false end
    return
  end
  M.ask(buf, false)
end

-- The question, and the write if the answer is yes; `quit` closes the
-- window after a successful one (:wq, :x).
function M.ask(buf, quit)
  if asking[buf] then return end
  asking[buf] = true
  local target = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":p")
  require("plato.bridge").ask(tidy(target) .. " is not yours to write. Save it as root?", "warn",
    { { key = "s", label = "Save as root" } },
    function(choice)
      asking[buf] = nil
      if choice == "s" and api.nvim_buf_is_valid(buf) then write(buf, target, quit) end
    end)
end

-- A WRITE, AS PLATO'S SAVE ASKS FOR ONE (the leader's Space w, a tab's
-- menu): this buffer's own way — asked about and written as root when it is
-- root's, an ordinary :write when it is not.
function M.save(all)
  local buf = api.nvim_get_current_buf()
  if vim.b[buf].plato_root then M.ask(buf, false); return end
  local ok, err = pcall(vim.cmd, all and "wall" or "write")
  if not ok then vim.notify((tostring(err):gsub("^.-:%d+: ", "")), vim.log.levels.ERROR) end
end

-- a file that is someone else's: plato writes it, and nvim is not to call
-- it read-only
local group = api.nvim_create_augroup("plato.root", { clear = true })
local function check(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local name = api.nvim_buf_get_name(buf)
  if name == "" or name:match("^%a+://") then return end
  local foreign = not M.writable(name)
  if foreign == (vim.b[buf].plato_root == true) then return end
  vim.b[buf].plato_root = foreign or nil
  api.nvim_clear_autocmds({ group = group, buffer = buf, event = "BufWriteCmd" })
  if foreign then
    vim.bo[buf].readonly = false
    api.nvim_create_autocmd("BufWriteCmd", { group = group, buffer = buf, callback = onWrite })
  end
end

function M.setup()
  api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost" }, {
    group = api.nvim_create_augroup("plato.root.watch", { clear = true }),
    callback = function(ev) check(ev.buf) end,
  })
end

return M
