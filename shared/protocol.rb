#==============================================================================
# Maruchi Shared Wire Protocol (Strictly Ruby 1.8.1 & Ruby 3.x compatible)
# Framing is handled at transport layer (4-byte big-endian length prefix).
# Payloads are UTF-8 tab-separated fields: TYPE\tfield1\tfield2...
#==============================================================================
module Maruchi
  module Protocol
    VERSION = 1

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

    def self.build_state_update(seq, x, y, real_x, real_y, dir, moving, char_name, char_index, actor_id, dir8, btn_mask)
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
        btn_mask.to_i
      )
    end

    def self.build_action(kind, action_id, dir)
      pack("ACTION", esc(kind), action_id.to_i, dir.to_i)
    end

    def self.build_ping(client_ms)
      pack("PING", client_ms.to_i)
    end

    # --- Server -> Client builders ---
    def self.build_welcome(player_id, map_id, spawn_x, spawn_y, mode, tick_rate)
      pack("WELCOME", player_id.to_i, map_id.to_i, spawn_x.to_i, spawn_y.to_i, esc(mode), tick_rate.to_i)
    end

    def self.build_map_transfer(map_id, spawn_x, spawn_y)
      pack("MAP", map_id.to_i, spawn_x.to_i, spawn_y.to_i)
    end

    def self.build_pong(client_ms, server_tick)
      pack("PONG", client_ms.to_i, server_tick.to_i)
    end

    def self.build_event(kind, *args)
      encoded = [ "EVENT", esc(kind) ]
      args.each { |a| encoded.push(esc(a)) }
      encoded.join("\t")
    end

    # players: array of hashes with :id,:name,:actor_id,:team,:x,:y,:real_x,:real_y,:dir,:char_name,:char_index,:hp,:maxhp,:moving
    # enemies: array of hashes with :id,:x,:y,:real_x,:real_y,:dir,:hp,:maxhp,:erased
    def self.build_snapshot(server_tick, map_id, players, enemies)
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
          p[:moving] ? 1 : 0
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
          e[:erased] ? 1 : 0
        ].join(",")
      end.join(";")

      pack("SNAP", server_tick.to_i, map_id.to_i, p_blob, e_blob)
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
          :moving     => (f[13].to_i != 0)
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
          :id     => f[0].to_i,
          :x      => f[1].to_i,
          :y      => f[2].to_i,
          :real_x => f[3].to_i,
          :real_y => f[4].to_i,
          :dir    => f[5].to_i,
          :hp     => f[6].to_i,
          :maxhp  => f[7].to_i,
          :erased => (f[8].to_i != 0)
        })
      end
      result
    end
  end
end
