#==============================================================================
# Maruchi Native 32-bit Network Bridge (RGSS2 / Ruby 1.8.1 -> maruchi_net.dll)
# All blocking I/O runs on a background Rust OS thread so 60fps never stalls.
#==============================================================================
module Maruchi
  module Net
    STATE_DISCONNECTED = 0
    STATE_CONNECTING   = 1
    STATE_CONNECTED    = 2
    STATE_ERROR        = 3

    DLL_CANDIDATES = [
      File.join(Dir.pwd, "maruchi_net.dll"),
      File.join(Maruchi::ROOT_DIR, "game", "maruchi_net.dll"),
      File.join(Maruchi::ROOT_DIR, "native", "maruchi_net", "target", "i686-pc-windows-msvc", "release", "maruchi_net.dll"),
      "maruchi_net.dll"
    ]

    @loaded = false
    @dll_path = nil
    @fn_connect = nil
    @fn_disconnect = nil
    @fn_state = nil
    @fn_send = nil
    @fn_poll = nil
    @fn_last_error = nil
    @fn_bg_run = nil
    @fn_focused = nil
    @poll_buf = "\0" * 65536
    @err_buf  = "\0" * 1024

    def self.available?
      ensure_loaded
      @loaded
    end

    def self.ensure_loaded
      return if @loaded
      DLL_CANDIDATES.each do |cand|
        if File.exist?(cand)
          @dll_path = cand
          break
        end
      end
      if @dll_path.nil?
        Maruchi::Log.warn("maruchi_net.dll not found in candidates; networking disabled.")
        return
      end
      begin
        @fn_connect    = Win32API.new(@dll_path, "maruchi_connect",    ["p", "l"], "l")
        @fn_disconnect = Win32API.new(@dll_path, "maruchi_disconnect", [],         "l")
        @fn_state      = Win32API.new(@dll_path, "maruchi_state",      [],         "l")
        @fn_send       = Win32API.new(@dll_path, "maruchi_send",       ["p", "l"], "l")
        @fn_poll       = Win32API.new(@dll_path, "maruchi_poll",       ["p", "l"], "l")
        @fn_last_error = Win32API.new(@dll_path, "maruchi_last_error", ["p", "l"], "l")
        @fn_bg_run     = Win32API.new(@dll_path, "maruchi_enable_background_run", [], "l")
        @fn_focused    = Win32API.new(@dll_path, "maruchi_window_focused",        [], "l")
        @loaded = true
        Maruchi::Log.info("Loaded maruchi_net.dll from #{@dll_path}")
      rescue Exception => e
        Maruchi::Log.error("Failed to bind maruchi_net.dll: #{e.class}: #{e.message}")
        @loaded = false
      end
    end

    def self.connect(host, port)
      ensure_loaded
      return false unless @loaded
      begin
        # Ruby 1.8.1 Win32API "p" args require an unfrozen String (ENV values are frozen)
        host_buf = host.to_s.dup
        ret = @fn_connect.call(host_buf, port.to_i)
        Maruchi::Log.info("maruchi_connect(#{host_buf}, #{port}) => #{ret}, state=#{state}")
        return ret == 1
      rescue Exception => e
        Maruchi::Log.error("connect exception: #{e.class}: #{e.message}")
        return false
      end
    end

    def self.disconnect
      return false unless @loaded
      @fn_disconnect.call == 1
    end

    def self.state
      return STATE_DISCONNECTED unless @loaded
      @fn_state.call
    end

    def self.connected?
      state == STATE_CONNECTED
    end

    def self.connecting?
      state == STATE_CONNECTING
    end

    def self.send_msg(str)
      return false unless @loaded
      s = str.to_s.dup
      return false if s.empty?
      @fn_send.call(s, s.length) == 1
    end

    def self.poll_one
      return nil unless @loaded
      n = @fn_poll.call(@poll_buf, @poll_buf.length)
      return nil if n == 0
      if n < 0
        # Buffer too small; resize and retry once
        need = -n
        @poll_buf = "\0" * (need + 1024)
        n = @fn_poll.call(@poll_buf, @poll_buf.length)
        return nil if n <= 0
      end
      @poll_buf[0, n]
    end

    def self.poll_all(max_count = 64)
      msgs = []
      count = 0
      while count < max_count
        msg = poll_one
        break if msg.nil?
        msgs.push(msg)
        count += 1
      end
      msgs
    end

    def self.last_error
      return "" unless @loaded
      n = @fn_last_error.call(@err_buf, @err_buf.length)
      return "" if n <= 0
      @err_buf[0, n]
    end

    def self.enable_background_run
      ensure_loaded
      return false unless @loaded && @fn_bg_run
      @fn_bg_run.call == 1
    end

    def self.window_focused?
      return true unless @loaded && @fn_focused
      @fn_focused.call == 1
    end
  end
end
