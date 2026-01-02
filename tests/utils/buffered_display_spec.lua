local BufferedDisplay = require("avante.utils.buffered_display")

describe("BufferedDisplay", function()
  describe("basic functionality", function()
    it("should create a new instance", function()
      local display = BufferedDisplay:new(function() end)
      assert.is_not_nil(display)
      assert.is_nil(display:get())
    end)

    it("should display content character by character", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      display:enqueue("test")

      -- Wait for all characters to be processed (4 chars * 20ms + buffer)
      vim.wait(150, function() return #results >= 4 end)

      assert.equals(4, #results)
      assert.equals("t", results[1])
      assert.equals("te", results[2])
      assert.equals("tes", results[3])
      assert.equals("test", results[4])
      assert.equals("test", display:get())
    end)

    it("should clear all state", function()
      local display = BufferedDisplay:new(function() end)

      display:enqueue("test")
      display:clear()

      assert.is_nil(display:get())
    end)
  end)

  describe("incremental updates", function()
    it("should append to existing content when new content is prefixed correctly", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      display:enqueue("Hello")
      vim.wait(150, function() return display:get() == "Hello" end)

      local count_after_first = #results
      display:enqueue("Hello World")

      vim.wait(150, function() return display:get() == "Hello World" end)

      -- Should only add " World" characters, not restart from beginning
      assert.equals("Hello World", display:get())
      -- Verify it didn't restart (would have more results if it did)
      assert.is_true(#results < count_after_first + 11)
    end)

    it("should continue from queued content", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      -- Start with some content
      display:enqueue("abc")

      -- Immediately enqueue more before first finishes processing
      display:enqueue("abcdef")

      -- Wait for completion
      vim.wait(200, function() return display:get() == "abcdef" end)

      assert.equals("abcdef", display:get())
    end)
  end)

  describe("content replacement", function()
    it("should replace content when new content doesn't match prefix", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      display:enqueue("Hello")
      vim.wait(150, function() return display:get() == "Hello" end)

      results = {}
      display:enqueue("World")

      vim.wait(150, function() return display:get() == "World" end)

      -- Should have restarted from scratch
      assert.equals(5, #results)
      assert.equals("W", results[1])
      assert.equals("World", display:get())
    end)

    it("should replace content when prefix doesn't match displayed + queued", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      -- Queue "test"
      display:enqueue("test")

      -- Before it finishes, try to enqueue something that doesn't continue from "test"
      display:enqueue("different")

      vim.wait(250, function() return display:get() == "different" end)

      assert.equals("different", display:get())
    end)

    it("should handle rapid content changes correctly", function()
      local last_content
      local display = BufferedDisplay:new(function(content) last_content = content end)

      -- Simulate rapid title changes
      display:enqueue("Loading...")
      display:enqueue("Processing...")
      display:enqueue("Complete!")

      vim.wait(350, function() return display:get() == "Complete!" end)

      assert.equals("Complete!", display:get())
      assert.equals("Complete!", last_content)
    end)
  end)

  describe("edge cases", function()
    it("should handle empty string", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      display:enqueue("")

      -- Should not process anything
      vim.wait(50, function() return false end)

      assert.equals(0, #results)
      assert.is_nil(display:get())
    end)

    it("should handle single character", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      display:enqueue("a")

      vim.wait(50, function() return display:get() == "a" end)

      assert.equals(1, #results)
      assert.equals("a", display:get())
    end)

    it("should handle special characters", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      local special = "test\n\t\r"
      display:enqueue(special)

      vim.wait(150, function() return display:get() == special end)

      assert.equals(special, display:get())
    end)

    it("should handle unicode characters", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      -- Note: The implementation splits by byte, not character, so multi-byte unicode
      -- characters may not display correctly during animation but final result should be correct
      local unicode = "Hello World"
      display:enqueue(unicode)

      vim.wait(300, function() return display:get() == unicode end)

      assert.equals(unicode, display:get())
    end)
  end)

  describe("timer management", function()
    it("should not start multiple timers", function()
      local call_count = 0
      local display = BufferedDisplay:new(function() call_count = call_count + 1 end)

      display:enqueue("test")
      display:enqueue("test more")
      display:enqueue("test more content")

      vim.wait(500, function() return display:get() == "test more content" end)

      -- Should have the right number of character updates
      -- "test more content" = 18 characters, but timing may cause slight variance
      assert.is_true(call_count >= 17 and call_count <= 19, "Expected ~18 calls, got " .. call_count)
    end)

    it("should stop timer when cleared", function()
      local call_count = 0
      local display = BufferedDisplay:new(function() call_count = call_count + 1 end)

      display:enqueue("long content string")
      vim.wait(30, function() return false end)

      local count_before_clear = call_count
      display:clear()

      vim.wait(100, function() return false end)

      -- Should not have processed more after clear
      assert.equals(count_before_clear, call_count)
      assert.is_nil(display:get())
    end)
  end)

  describe("bug fix: overlapping characters", function()
    it("should not overlap characters when replacing title", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      -- First title
      display:enqueue("Title One")
      vim.wait(250, function() return display:get() == "Title One" end)
      assert.equals("Title One", display:get())

      -- Clear results to track only new updates
      results = {}

      -- Second title (completely different)
      display:enqueue("New Title")
      vim.wait(250, function() return display:get() == "New Title" end)

      -- Should show new title, not overlap
      assert.equals("New Title", display:get())

      -- First result should be "N", not "TitleN" or similar
      assert.equals("N", results[1])
    end)

    it("should correctly handle queue state when checking prefix", function()
      local display = BufferedDisplay:new(function() end)

      -- Enqueue content that will take time to process
      display:enqueue("abcdefghij")

      -- Immediately enqueue different content before first is done
      display:enqueue("xyz")

      -- Wait for processing
      vim.wait(300, function() return display:get() == "xyz" end)

      -- Should show xyz, not some overlap of both
      assert.equals("xyz", display:get())
    end)

    it("should handle progressive updates correctly", function()
      local results = {}
      local display = BufferedDisplay:new(function(content) table.insert(results, content) end)

      -- Simulate streaming response
      display:enqueue("The")
      vim.wait(80, function() return #results >= 3 end)

      display:enqueue("The quick")
      vim.wait(160, function() return display:get() == "The quick" end)

      display:enqueue("The quick brown")
      vim.wait(160, function() return display:get() == "The quick brown" end)

      assert.equals("The quick brown", display:get())

      -- Verify we didn't restart from beginning multiple times
      -- Should have approximately 15 characters worth of updates
      assert.is_true(#results <= 20) -- Allow some margin
    end)
  end)
end)
