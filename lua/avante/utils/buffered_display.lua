---@class avante.BufferedDisplay
---@field private _char_queue string[]
---@field private _timer table|nil
---@field private _displayed_content string|nil
---@field private _on_update fun(content: string): nil
---@field private _interval integer
local BufferedDisplay = {}
BufferedDisplay.__index = BufferedDisplay

---Creates a new BufferedDisplay instance
---@param on_update fun(content: string): nil Callback invoked when the displayed content updates
---@return avante.BufferedDisplay
function BufferedDisplay:new(on_update)
  return setmetatable({
    _char_queue = {},
    _timer = nil,
    _displayed_content = nil,
    _on_update = on_update,
    _interval = 20,
  }, BufferedDisplay)
end

---Adds content to the queue and starts processing if not already running
---@param content string Content to be displayed, will replace the previously enqueued content
function BufferedDisplay:enqueue(content)
  local displayed = self._displayed_content or ""
  local queued = table.concat(self._char_queue)
  local target = displayed .. queued

  -- Check if the new content is prefixed by the target content (displayed + queued)
  if content:sub(1, #target) ~= target then
    -- New content doesn't continue from current state, start fresh
    self._displayed_content = nil
    self._char_queue = {}
    displayed = ""
    target = ""
  end

  -- Add only the new characters that aren't already in target (displayed + queued)
  for i = #target + 1, #content do
    self._char_queue[#self._char_queue + 1] = content:sub(i, i)
  end

  -- If timer is already running, the content will be processed in sequence
  if self._timer then return end

  -- Start processing the queue
  self:_process_next()
end

---Internal method to process the next content in the queue
---@private
function BufferedDisplay:_process_next()
  -- Check if there are more items to process
  if #self._char_queue == 0 then
    -- No more items, clear the timer
    self._timer = nil
    return
  end

  -- Take the first character from the queue
  local next_char = table.remove(self._char_queue, 1)

  -- Update the displayed content
  self._displayed_content = (self._displayed_content or "") .. next_char

  -- Notify via callback
  self._on_update(self._displayed_content)

  -- Schedule the next content processing
  self._timer = vim.defer_fn(function() self:_process_next() end, self._interval)
end

---Gets the current displayed content
---@return string|nil
function BufferedDisplay:get() return self._displayed_content end

---Stops processing and clears all state
function BufferedDisplay:clear()
  -- Clear the queue
  self._char_queue = {}

  -- Stop the timer if running
  if self._timer then pcall(function() self._timer:stop() end) end
  self._timer = nil

  -- Clear the displayed content
  self._displayed_content = nil
end

return BufferedDisplay
