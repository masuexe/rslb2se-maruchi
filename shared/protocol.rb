#==============================================================================
# Maruchi Shared Wire Protocol (Strictly Ruby 1.8.1 & Ruby 3.x compatible)
# Framing is handled at transport layer (4-byte big-endian length prefix).
# Payloads are UTF-8 tab-separated fields: TYPE\tfield1\tfield2...
#==============================================================================
module Maruchi
  module Protocol
    VERSION = 4

    # Escapes delimiters (\t, \n, \r, ;, ,, %) so arbitrary UTF-8 strings (Chinese names, filenames) are safe
    def self.esc(str)
      s = str.to_s.dup
      s.gsub!("%", "%25")
      s.gsub!("\t", "%09")
      s.gsub!("\n", "%0A")
      s.gsub!("\r", "%0D")
      s.gsub!(";", "%3B")
      s.gsub!(",", "%2C")
      s
    end

    def self.unesc(str)
      return "" if str.nil?
      s = str.to_s.dup
      s.gsub!("%2C", ",")
      s.gsub!("%3B", ";")
      s.gsub!("%0D", "\r")
      s.gsub!("%0A", "\n")
      s.gsub!("%09", "\t")
      s.gsub!("%25", "%")
      s
    end

    def self.pack(*fields)
      fields.collect { |f| f.to_s }.join("\t")
    end

    def self.unpack(payload)
      return [] if payload.nil? || payload.empty?
      payload.split("\t", -1)
    end

    # --- Client -> Server builders ---
    def self.build_hello(name, actor_id)
      pack("HELLO", VERSION, esc(name), actor_id.to_i)
    end

    def self.build_state_update(seq, x, y, real_x, real_y, dir, moving, char_name, char_index, actor_id, dir8, btn_mask, pattern = 1, step_anime = false)
      pack(
        "PSTATE",
        seq.to_i,
        x.to_i,
        y.to_i,
        real_x.to_i,
        real_y.to_i,
        dir.to_i,
        moving ? 1 : 0,
        esc(char_name),
        char_index.to_i,
        actor_id.to_i,
        dir8.to_i,
        btn_mask.to_i,
        pattern.to_i,
        step_anime ? 1 : 0
      )
    end

    def self.build_action(kind, action_id, dir, dir8 = 0)
      pack("ACTION", esc(kind), action_id.to_i, dir.to_i, dir8.to_i)
    end

    def self.build_req_actor(actor_id)
      pack("REQ_ACTOR", actor_id.to_i)
    end

    def self.build_req_transfer(map_id, x = -1, y = -1, dir = 2)
      pack("REQ_TRANSFER", map_id.to_i, x.to_i, y.to_i, dir.to_i)
    end

    def self.build_req_mode(mode)
      pack("REQ_MODE", esc(mode))
    end

    def self.build_req_interact(x, y, dir)
      pack("REQ_INTERACT", x.to_i, y.to_i, dir.to_i)
    end

    def self.build_ping(client_ms)
      pack("PING", client_ms.to_i)
    end

    # --- Server -> Client builders ---
    def self.build_welcome(player_id, map_id, spawn_x, spawn_y, mode, tick_rate)
      pack("WELCOME", player_id.to_i, map_id.to_i, spawn_x.to_i, spawn_y.to_i, esc(mode), tick_rate.to_i)
    end

    def self.build_map_transfer(map_id, spawn_x, spawn_y, dir = 2)
      pack("MAP", map_id.to_i, spawn_x.to_i, spawn_y.to_i, dir.to_i)
    end

    # Full world sync of non-default switches, variables, and current-map self switches
    # sw_ids: array of integer switch IDs that are true
    # var_pairs: array of [var_id, int_val] for non-zero variables
    # ssw_entries: array of [map_id, ev_id, ch, bool]
    def self.build_world_sync(sw_ids, var_pairs, ssw_entries)
      sw_blob  = (sw_ids || []).collect { |id| id.to_i.to_s }.join(",")
      var_blob = (var_pairs || []).collect { |pair| "#{pair[0].to_i},#{pair[1].to_i}" }.join(";")
      ssw_blob = (ssw_entries || []).collect { |e| "#{e[0].to_i},#{e[1].to_i},#{esc(e[2])},#{e[3] ? 1 : 0}" }.join(";")
      pack("WORLD_SYNC", sw_blob, var_blob, ssw_blob)
    end

    def self.parse_world_sync(sw_blob, var_blob, ssw_blob)
      sw = []
      if sw_blob && !sw_blob.empty?
        sw_blob.split(",").each { |s| sw.push(s.to_i) unless s.empty? }
      end
      vars = []
      if var_blob && !var_blob.empty?
        var_blob.split(";").each do |rec|
          next if rec.empty?
          f = rec.split(",", -1)
          vars.push([f[0].to_i, f[1].to_i]) if f.length >= 2
        end
      end
      ssw = []
      if ssw_blob && !ssw_blob.empty?
        ssw_blob.split(";").each do |rec|
          next if rec.empty?
          f = rec.split(",", -1)
          ssw.push([f[0].to_i, f[1].to_i, unesc(f[2]), (f[3].to_i != 0)]) if f.length >= 4
        end
      end
      { :switches => sw, :variables => vars, :self_switches => ssw }
    end

    def self.build_pong(client_ms, server_tick)
      pack("PONG", client_ms.to_i, server_tick.to_i)
    end

    def self.build_event(kind, *args)
      encoded = [ "EVENT", esc(kind) ]
      args.each { |a| encoded.push(esc(a)) }
      encoded.join("\t")
    end

    # players: array of hashes with :id,:name,:actor_id,:team,:x,:y,:real_x,:real_y,:dir,:char_name,:char_index,:hp,:maxhp,:moving,:pattern,:step_anime,:mp,:maxmp,:down_timer
    # enemies: array of hashes with :id,:x,:y,:real_x,:real_y,:dir,:hp,:maxhp,:erased,:opacity,:collapse_dur,:defeated
    # tokens:  array of hashes with :id,:kind,:x,:y,:real_x,:real_y,:dir,:char_name,:char_index,:pattern,:opacity,:blend_type,:angle,:zoom_x,:zoom_y,:icon_name,:jump_y
    def self.build_snapshot(server_tick, map_id, players, enemies, tokens = [])
      p_blob = players.collect do |p|
        [
          p[:id].to_i,
          esc(p[:name]),
          p[:actor_id].to_i,
          p[:team].to_i,
          p[:x].to_i,
          p[:y].to_i,
          p[:real_x].to_i,
          p[:real_y].to_i,
          p[:dir].to_i,
          esc(p[:char_name]),
          p[:char_index].to_i,
          p[:hp].to_i,
          p[:maxhp].to_i,
          p[:moving] ? 1 : 0,
          (p[:pattern] || 1).to_i,
          p[:step_anime] ? 1 : 0,
          p[:mp].to_i,
          p[:maxmp].to_i,
          p[:down_timer].to_i
        ].join(",")
      end.join(";")

      e_blob = enemies.collect do |e|
        [
          e[:id].to_i,
          e[:x].to_i,
          e[:y].to_i,
          e[:real_x].to_i,
          e[:real_y].to_i,
          e[:dir].to_i,
          e[:hp].to_i,
          e[:maxhp].to_i,
          e[:erased] ? 1 : 0,
          (e[:opacity].nil? ? 255 : e[:opacity].to_i),
          e[:collapse_dur].to_i,
          e[:defeated] ? 1 : 0
        ].join(",")
      end.join(";")

      t_blob = (tokens || []).collect do |t|
        [
          t[:id].to_i,
          t[:kind].to_i,
          t[:x].to_i,
          t[:y].to_i,
          t[:real_x].to_i,
          t[:real_y].to_i,
          t[:dir].to_i,
          esc(t[:char_name]),
          t[:char_index].to_i,
          t[:pattern].to_i,
          (t[:opacity].nil? ? 255 : t[:opacity].to_i),
          t[:blend_type].to_i,
          t[:angle].to_i,
          t[:zoom_x].to_i,
          t[:zoom_y].to_i,
          (t[:icon_name].nil? ? -1 : t[:icon_name].to_i),
          t[:jump_y].to_i
        ].join(",")
      end.join(";")

      pack("SNAP", server_tick.to_i, map_id.to_i, p_blob, e_blob, t_blob)
    end

    def self.parse_snapshot_players(blob)
      result = []
      return result if blob.nil? || blob.empty?
      blob.split(";").each do |rec|
        next if rec.empty?
        f = rec.split(",", -1)
        next if f.length < 14
        result.push({
          :id         => f[0].to_i,
          :name       => unesc(f[1]),
          :actor_id   => f[2].to_i,
          :team       => f[3].to_i,
          :x          => f[4].to_i,
          :y          => f[5].to_i,
          :real_x     => f[6].to_i,
          :real_y     => f[7].to_i,
          :dir        => f[8].to_i,
          :char_name  => unesc(f[9]),
          :char_index => f[10].to_i,
          :hp         => f[11].to_i,
          :maxhp      => f[12].to_i,
          :moving     => (f[13].to_i != 0),
          :pattern    => (f.length > 14 ? f[14].to_i : 1),
          :step_anime => (f.length > 15 ? (f[15].to_i != 0) : false),
          :mp         => (f.length > 16 ? f[16].to_i : 0),
          :maxmp      => (f.length > 17 ? f[17].to_i : 0),
          :down_timer => (f.length > 18 ? f[18].to_i : 0)
        })
      end
      result
    end

    def self.parse_snapshot_enemies(blob)
      result = []
      return result if blob.nil? || blob.empty?
      blob.split(";").each do |rec|
        next if rec.empty?
        f = rec.split(",", -1)
        next if f.length < 9
        result.push({
          :id           => f[0].to_i,
          :x            => f[1].to_i,
          :y            => f[2].to_i,
          :real_x       => f[3].to_i,
          :real_y       => f[4].to_i,
          :dir          => f[5].to_i,
          :hp           => f[6].to_i,
          :maxhp        => f[7].to_i,
          :erased       => (f[8].to_i != 0),
          :opacity      => (f.length > 9  ? f[9].to_i : 255),
          :collapse_dur => (f.length > 10 ? f[10].to_i : 0),
          :defeated     => (f.length > 11 ? (f[11].to_i != 0) : false)
        })
      end
      result
    end

    def self.parse_snapshot_tokens(blob)
      result = []
      return result if blob.nil? || blob.empty?
      blob.split(";").each do |rec|
        next if rec.empty?
        f = rec.split(",", -1)
        next if f.length < 17
        icon_raw = f[15].to_i
        result.push({
          :id         => f[0].to_i,
          :kind       => f[1].to_i,
          :x          => f[2].to_i,
          :y          => f[3].to_i,
          :real_x     => f[4].to_i,
          :real_y     => f[5].to_i,
          :dir        => f[6].to_i,
          :char_name  => unesc(f[7]),
          :char_index => f[8].to_i,
          :pattern    => f[9].to_i,
          :opacity    => f[10].to_i,
          :blend_type => f[11].to_i,
          :angle      => f[12].to_i,
          :zoom_x     => f[13].to_i,
          :zoom_y     => f[14].to_i,
          :icon_name  => (icon_raw >= 0 ? icon_raw : nil),
          :jump_y     => f[16].to_i
        })
      end
      result
    end
  end
end
