#==============================================================================
# Maruchi Client Configuration (Ruby 1.8.1 compatible)
# Precedence: Environment variables > maruchi.ini > built-in defaults
#   ENV overrides: MARUCHI_HOST, MARUCHI_PORT, MARUCHI_NAME,
#                  MARUCHI_ACTOR_ID, MARUCHI_AUTO_JOIN
#==============================================================================
module Maruchi
  module Config
    def self.load_ini
      cfg = {}
      candidates = [
        File.join(Dir.pwd, "maruchi.ini"),
        File.join(Maruchi::ROOT_DIR, "maruchi.ini"),
        File.join(Maruchi::CLIENT_DIR, "maruchi.ini")
      ]
      ini_path = nil
      candidates.each do |p|
        if File.file?(p)
          ini_path = p
          break
        end
      end
      return [cfg, nil] if ini_path.nil?
      begin
        raw = File.open(ini_path, "rb") { |f| f.read }
        # Strip UTF-8 BOM if saved by Windows Notepad (Ruby 1.8.1 & 3.x safe)
        raw = raw[3..-1] if raw && raw.length >= 3 && raw[0, 3] == "\xEF\xBB\xBF"
        raw.split(/\r?\n/).each do |line|
          s = line.strip
          next if s.empty? || s[0, 1] == "#" || s[0, 1] == ";" || s[0, 1] == "["
          idx = s.index("=")
          next if idx.nil?
          k = s[0, idx].strip.downcase
          v = s[(idx + 1)..-1].strip
          cfg[k] = v unless k.empty?
        end
      rescue Exception
      end
      [cfg, ini_path]
    end

    def self.pick_str(env_key, ini_hash, ini_key, default_val)
      if ENV[env_key] && !ENV[env_key].strip.empty?
        return ENV[env_key].strip
      end
      if ini_hash[ini_key] && !ini_hash[ini_key].empty?
        return ini_hash[ini_key]
      end
      default_val
    end

    def self.pick_int(env_key, ini_hash, ini_key, default_val)
      s = pick_str(env_key, ini_hash, ini_key, nil)
      (s && s.to_i > 0) ? s.to_i : default_val
    end

    def self.pick_bool(env_key, ini_hash, ini_key, default_val)
      s = pick_str(env_key, ini_hash, ini_key, nil)
      return default_val if s.nil?
      v = s.downcase
      (v == "1" || v == "true" || v == "yes" || v == "on")
    end

    INI_VALUES, INI_PATH = load_ini

    SERVER_HOST = pick_str("MARUCHI_HOST", INI_VALUES, "host", "127.0.0.1")
    SERVER_PORT = pick_int("MARUCHI_PORT", INI_VALUES, "port", 27890)
    PLAYER_NAME = pick_str("MARUCHI_NAME", INI_VALUES, "name", "Player_#{Process.pid % 1000}")
    ACTOR_ID    = pick_int("MARUCHI_ACTOR_ID", INI_VALUES, "actor_id", 1)
    AUTO_JOIN   = pick_bool("MARUCHI_AUTO_JOIN", INI_VALUES, "auto_join", false)

    # Logging
    LOG_TO_FILE = true
    LOG_TO_CONSOLE = true

    # Feature / Mod toggles (can be toggled independently)
    MODS = {
      :banner => true,
      :background_run => true,
      :coop_client => true,
      :mouse_support => false   # Planned QoL mod
    }
  end
end
