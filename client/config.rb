#==============================================================================
# Maruchi Client Configuration (Ruby 1.8.1 compatible)
# Environment variables override defaults for quick testing:
#   MARUCHI_HOST, MARUCHI_PORT, MARUCHI_NAME, MARUCHI_ACTOR_ID, MARUCHI_AUTO_JOIN
#==============================================================================
module Maruchi
  module Config
    SERVER_HOST = (ENV["MARUCHI_HOST"] && !ENV["MARUCHI_HOST"].empty?) ? ENV["MARUCHI_HOST"] : "127.0.0.1"
    SERVER_PORT = (ENV["MARUCHI_PORT"] && ENV["MARUCHI_PORT"].to_i > 0) ? ENV["MARUCHI_PORT"].to_i : 27890
    PLAYER_NAME = (ENV["MARUCHI_NAME"] && !ENV["MARUCHI_NAME"].empty?) ? ENV["MARUCHI_NAME"] : "Player_#{Process.pid % 1000}"
    ACTOR_ID    = (ENV["MARUCHI_ACTOR_ID"] && ENV["MARUCHI_ACTOR_ID"].to_i > 0) ? ENV["MARUCHI_ACTOR_ID"].to_i : 1
    AUTO_JOIN   = (ENV["MARUCHI_AUTO_JOIN"] == "1")

    # Logging
    LOG_TO_FILE = true
    LOG_TO_CONSOLE = true

    # Feature / Mod toggles (can be toggled independently)
    MODS = {
      :banner => true,
      :coop_client => true,
      :mouse_support => false   # Planned QoL mod
    }
  end
end
