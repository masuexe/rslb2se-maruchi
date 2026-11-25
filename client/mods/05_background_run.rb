#==============================================================================
# Background 60fps Execution & Focus-Gated Input (Ruby 1.8.1 / RGSS2)
# - Subclasses the RGSS Player WndProc via maruchi_net.dll so the game keeps
#   rendering & polling network packets at 60fps even when unfocused.
# - Masks Input queries while unfocused so typing in another window / P1
#   never leaks keystrokes into an unfocused game window.
#==============================================================================
if Maruchi::Config::MODS[:background_run]
  module Maruchi
    module BackgroundRun
      @enabled = false
      @focused = true

      def self.activate!
        return if @enabled
        if Maruchi::Net.enable_background_run
          @enabled = true
          Maruchi::Log.info("Background 60fps mode enabled (focus-gated input active).")
        else
          Maruchi::Log.warn("Background 60fps mode failed to hook RGSS Player window (will retry).")
        end
      end

      def self.refresh_focus!
        @focused = Maruchi::Net.window_focused?
      end

      def self.focused?
        @focused
      end

      def self.enabled?
        @enabled
      end
    end
  end

  module Input
    class << self
      alias maruchi_bg_update update
      def update
        maruchi_bg_update
        Maruchi::BackgroundRun.refresh_focus!
      end

      alias maruchi_bg_press? press?
      def press?(sym)
        return false unless Maruchi::BackgroundRun.focused?
        maruchi_bg_press?(sym)
      end

      alias maruchi_bg_trigger? trigger?
      def trigger?(sym)
        return false unless Maruchi::BackgroundRun.focused?
        maruchi_bg_trigger?(sym)
      end

      alias maruchi_bg_repeat? repeat?
      def repeat?(sym)
        return false unless Maruchi::BackgroundRun.focused?
        maruchi_bg_repeat?(sym)
      end

      alias maruchi_bg_dir4 dir4
      def dir4
        return 0 unless Maruchi::BackgroundRun.focused?
        maruchi_bg_dir4
      end

      alias maruchi_bg_dir8 dir8
      def dir8
        return 0 unless Maruchi::BackgroundRun.focused?
        maruchi_bg_dir8
      end
    end
  end

  class Scene_Title
    alias maruchi_bg_title_start start
    def start
      Maruchi::BackgroundRun.activate!
      maruchi_bg_title_start
    end
  end

  class Scene_Map
    alias maruchi_bg_map_start start
    def start
      Maruchi::BackgroundRun.activate! unless Maruchi::BackgroundRun.enabled?
      maruchi_bg_map_start
    end
  end
end
