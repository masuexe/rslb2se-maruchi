#==============================================================================
# Maruchi Client Configuration (Ruby 1.8.1 compatible)
#==============================================================================
module Maruchi
  module Config
    # Server connection settings (used in Step 3+)
    SERVER_HOST = "127.0.0.1"
    SERVER_PORT = 27890
    PLAYER_NAME = "Player"

    # Logging
    LOG_TO_FILE = true
    LOG_TO_CONSOLE = true

    # Feature / Mod toggles (can be toggled independently)
    MODS = {
      :banner => true,
      :mouse_support => false,   # Planned QoL mod
      :coop_client => false      # Planned multiplayer client
    }
  end
end
