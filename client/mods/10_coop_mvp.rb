#==============================================================================
# Maruchi Step 3 Co-op MVP Client (Ruby 1.8.1 / RGSS2 compatible)
# - Press F7 on Title or Map to connect/join the headless server (or AUTO_JOIN=1)
# - Renders remote players with smooth real_x/real_y interpolation & name tags
# - Syncs authoritative enemy positions & HP from the headless server
# - Forwards local XAS weapon shots (shoot) to the server
#==============================================================================
if Maruchi::Config::MODS[:coop_client]

  #----------------------------------------------------------------------------
  # Remote player entity rendered by Sprite_Character on Spriteset_Map
  #----------------------------------------------------------------------------
  class Game_RemotePlayer < Game_Character
    attr_accessor :player_id, :player_name, :actor_id, :team, :hp, :maxhp
    attr_accessor :target_real_x, :target_real_y, :remote_moving
    attr_accessor :erased, :can_update, :throw_active, :battler

    def initialize(player_id, name)
      super()
      @player_id = player_id
      @player_name = name.to_s
      @actor_id = 1
      @team = 0
      @hp = 100
      @maxhp = 100
      @erased = false
      @can_update = true
      @throw_active = false
      @battler = nil
      @through = true
      @walk_anime = true
      @step_anime = false
      @priority_type = 1
      @target_real_x = 0
      @target_real_y = 0
      @remote_moving = false
      @initialized_pos = false
    end

    def apply_snapshot(p)
      @player_name = p[:name] if p[:name] && !p[:name].empty?
      @actor_id    = p[:actor_id]
      @team        = p[:team]
      @hp          = p[:hp]
      @maxhp       = p[:maxhp]
      @direction   = p[:dir] if [2, 4, 6, 8].include?(p[:dir])
      @x           = p[:x]
      @y           = p[:y]
      @target_real_x = p[:real_x]
      @target_real_y = p[:real_y]
      @remote_moving = p[:moving]

      if p[:char_name] && !p[:char_name].empty?
        if @character_name != p[:char_name] || @character_index != p[:char_index]
          @character_name  = p[:char_name]
          @character_index = p[:char_index]
        end
      end

      unless @initialized_pos
        @real_x = @target_real_x
        @real_y = @target_real_y
        @initialized_pos = true
      end
    end

    def update
      # Smoothly interpolate toward latest authoritative real_x/real_y
      dx = @target_real_x - @real_x
      dy = @target_real_y - @real_y
      if dx.abs > 1024 || dy.abs > 1024
        # Snap on large teleport
        @real_x = @target_real_x
        @real_y = @target_real_y
      else
        @real_x += (dx / 3)
        @real_y += (dy / 3)
        @real_x = @target_real_x if dx.abs < 4
        @real_y = @target_real_y if dy.abs < 4
      end

      # Drive walking animation while moving or interpolating
      if @remote_moving || dx.abs > 8 || dy.abs > 8
        @anime_count += 1.5
        if @anime_count >= 12
          @pattern = (@pattern + 1) % 4
          @anime_count = 0
        end
      else
        @pattern = @original_pattern
        @anime_count = 0
      end
    end
  end

  #----------------------------------------------------------------------------
  # Overhead Name Tag Sprite for Remote Players
  #----------------------------------------------------------------------------
  class Sprite_RemoteNameTag < Sprite
    def initialize(viewport, character)
      super(viewport)
      @character = character
      @last_text = nil
      self.z = 210
      self.bitmap = Bitmap.new(128, 22)
      self.bitmap.font.size = 14
      self.bitmap.font.bold = true
      self.ox = 64
      self.oy = 56
      refresh_text
      update
    end

    def refresh_text
      text = @character.player_name.to_s
      return if text == @last_text
      @last_text = text
      self.bitmap.clear
      self.bitmap.font.color = Color.new(0, 0, 0, 200)
      self.bitmap.draw_text(1, 1, 128, 20, text, 1)
      self.bitmap.font.color = Color.new(120, 240, 255, 255)
      self.bitmap.draw_text(0, 0, 128, 20, text, 1)
    end

    def update
      super
      refresh_text
      self.x = @character.screen_x
      self.y = @character.screen_y
      self.visible = !@character.transparent
    end

    def dispose
      self.bitmap.dispose if self.bitmap && !self.bitmap.disposed?
      super
    end
  end

  #----------------------------------------------------------------------------
  # Tiny Top-Right Multiplayer Status HUD
  #----------------------------------------------------------------------------
  class Sprite_MaruchiHud < Sprite
    def initialize(viewport)
      super(viewport)
      self.z = 250
      self.x = 544 - 236
      self.y = 4
      self.bitmap = Bitmap.new(232, 24)
      self.bitmap.font.size = 13
      @last_str = nil
      update
    end

    def update
      super
      str = Maruchi::Coop.hud_text
      return if str == @last_str
      @last_str = str
      self.bitmap.clear
      self.bitmap.fill_rect(0, 0, 232, 22, Color.new(0, 0, 0, 140))
      self.bitmap.font.color = Maruchi::Coop.connected? ? Color.new(120, 255, 160) : Color.new(255, 220, 120)
      self.bitmap.draw_text(6, 1, 220, 20, str, 2)
    end

    def dispose
      self.bitmap.dispose if self.bitmap && !self.bitmap.disposed?
      super
    end
  end

  #----------------------------------------------------------------------------
  # Co-op Client Controller
  #----------------------------------------------------------------------------
  module Maruchi
    module Coop
      @active = false
      @hello_sent = false
      @welcomed = false
      @my_id = nil
      @server_map_id = nil
      @server_mode = "coop"
      @remote_players = {}
      @seq = 0
      @send_tick = 0
      @ping_tick = 0
      @rtt_ms = nil
      @pending_transfer = nil
      @last_state = Maruchi::Net::STATE_DISCONNECTED
      @status_note = "F7: Join Coop"

      def self.active?;         @active;         end
      def self.connected?;      @welcomed && Maruchi::Net.connected?; end
      def self.my_id;           @my_id;          end
      def self.remote_players;  @remote_players; end

      def self.hud_text
        if connected?
          cnt = @remote_players.size + 1
          ping_str = @rtt_ms ? " #{@rtt_ms}ms" : ""
          return "COOP P##{@my_id} (#{cnt}P)#{ping_str}"
        elsif @active && Maruchi::Net.connecting?
          return "COOP Connecting..."
        else
          return @status_note
        end
      end

      def self.connect_and_join(host = nil, port = nil)
        host ||= Maruchi::Config::SERVER_HOST
        port ||= Maruchi::Config::SERVER_PORT
        unless Maruchi::Net.available?
          @status_note = "DLL missing"
          Maruchi::Log.error("Cannot connect: maruchi_net.dll unavailable.")
          return false
        end
        @active = true
        @hello_sent = false
        @welcomed = false
        @my_id = nil
        @remote_players.clear
        @pending_transfer = nil
        @status_note = "Connecting..."
        Maruchi::Log.info("Connecting to #{host}:#{port} as '#{Maruchi::Config::PLAYER_NAME}'...")
        Maruchi::Net.connect(host, port)
      end

      def self.disconnect
        Maruchi::Net.disconnect
        @active = false
        @hello_sent = false
        @welcomed = false
        @my_id = nil
        @remote_players.clear
        @status_note = "Offline (F7)"
      end

      def self.ensure_map_scene_for_join(map_id, sx, sy)
        # Ensure we have a valid party actor (Map #161 intro starts with empty party)
        if $game_party && $game_party.members.empty?
          aid = Maruchi::Config::ACTOR_ID
          aid = 1 unless $data_actors && $data_actors[aid]
          $game_party.add_actor(aid)
        end

        if $game_map && $game_player
          $game_message.clear if $game_message
          $game_map.interpreter.clear if $game_map.interpreter
          if $game_map.map_id != map_id
            $game_map.setup(map_id)
            $game_player.moveto(sx, sy)
            $game_player.refresh
            $game_map.autoplay
            $scene = Scene_Map.new
          else
            $game_player.moveto(sx, sy)
            $game_player.refresh
          end
          Maruchi::Log.info("Entered live Coop Map ##{map_id} at (#{sx},#{sy}), actor=#{$game_party.members[0] ? $game_party.members[0].name : 'none'}")
        end
      end

      def self.send_action(kind, action_id, dir)
        return unless connected?
        Maruchi::Net.send_msg(Maruchi::Protocol.build_action(kind, action_id, dir))
      end

      def self.update
        return unless @active

        st = Maruchi::Net.state
        if st != @last_state
          @last_state = st
          if st == Maruchi::Net::STATE_ERROR
            err = Maruchi::Net.last_error
            @status_note = "Err (F7 retry)"
            @welcomed = false
            Maruchi::Log.error("Network error: #{err}")
          elsif st == Maruchi::Net::STATE_DISCONNECTED
            @status_note = "Disconnected (F7)"
            @welcomed = false
          end
        end

        if st == Maruchi::Net::STATE_CONNECTED && !@hello_sent
          aid = ($game_party && $game_party.members[0]) ? $game_party.members[0].id : Maruchi::Config::ACTOR_ID
          Maruchi::Net.send_msg(Maruchi::Protocol.build_hello(Maruchi::Config::PLAYER_NAME, aid))
          @hello_sent = true
          Maruchi::Log.info("Sent HELLO (name=#{Maruchi::Config::PLAYER_NAME}, actor=#{aid})")
        end

        # Drain inbound frames
        Maruchi::Net.poll_all(64).each do |payload|
          handle_message(payload)
        end

        # Update remote player interpolation
        @remote_players.each_value { |rp| rp.update }

        # Send local player state at 20Hz (every 3 frames) while on Scene_Map
        if connected? && $scene.is_a?(Scene_Map) && $game_player && $game_map
          @send_tick += 1
          if @send_tick >= 3
            @send_tick = 0
            @seq += 1
            aid = ($game_party && $game_party.members[0]) ? $game_party.members[0].id : Maruchi::Config::ACTOR_ID
            msg = Maruchi::Protocol.build_state_update(
              @seq,
              $game_player.x,
              $game_player.y,
              $game_player.real_x,
              $game_player.real_y,
              $game_player.direction,
              $game_player.moving?,
              $game_player.character_name,
              $game_player.character_index,
              aid,
              Input.dir8,
              0
            )
            Maruchi::Net.send_msg(msg)
          end

          @ping_tick += 1
          if @ping_tick >= 120
            @ping_tick = 0
            now_ms = (Time.now.to_f * 1000.0).to_i
            Maruchi::Net.send_msg(Maruchi::Protocol.build_ping(now_ms))
          end
        end
      end

      def self.handle_message(payload)
        f = Maruchi::Protocol.unpack(payload)
        return if f.empty?

        case f[0]
        when "WELCOME"
          @my_id         = f[1].to_i
          @server_map_id = f[2].to_i
          sx             = f[3].to_i
          sy             = f[4].to_i
          @server_mode   = Maruchi::Protocol.unesc(f[5])
          @welcomed      = true
          @status_note   = "Connected"
          Maruchi::Log.info("WELCOME received: my_id=#{@my_id}, map=#{@server_map_id} (#{sx},#{sy}), mode=#{@server_mode}")
          ensure_map_scene_for_join(@server_map_id, sx, sy)

        when "MAP"
          mid = f[1].to_i
          sx  = f[2].to_i
          sy  = f[3].to_i
          @server_map_id = mid
          ensure_map_scene_for_join(mid, sx, sy)

        when "SNAP"
          return unless @welcomed && @my_id
          # SNAP server_tick map_id players_blob enemies_blob
          snap_map = f[2].to_i
          players  = Maruchi::Protocol.parse_snapshot_players(f[3])
          enemies  = Maruchi::Protocol.parse_snapshot_enemies(f[4])

          seen_ids = {}
          players.each do |p|
            pid = p[:id]
            next if pid == @my_id
            seen_ids[pid] = true
            rp = @remote_players[pid]
            if rp.nil?
              rp = Game_RemotePlayer.new(pid, p[:name])
              @remote_players[pid] = rp
              Maruchi::Log.info("Spawned remote player ##{pid} '#{p[:name]}' at (#{p[:x]},#{p[:y]})")
            end
            rp.apply_snapshot(p)
          end
          # Remove disconnected players
          @remote_players.keys.each do |pid|
            unless seen_ids[pid]
              @remote_players.delete(pid)
              Maruchi::Log.info("Removed remote player ##{pid}")
            end
          end

          # Apply authoritative enemy coordinates & HP when on matching map
          if $scene.is_a?(Scene_Map) && $game_map && $game_map.map_id == snap_map
            apply_enemy_snapshots(enemies)
          end

        when "EVENT"
          kind = Maruchi::Protocol.unesc(f[1])
          Maruchi::Log.info("Server EVENT: #{kind} #{f[2..-1].inspect}")

        when "PONG"
          sent_ms = f[1].to_i
          now_ms  = (Time.now.to_f * 1000.0).to_i
          rtt = now_ms - sent_ms
          @rtt_ms = rtt if rtt >= 0 && rtt < 10000
        end
      end

      def self.apply_enemy_snapshots(enemies)
        enemies.each do |e|
          ev = $game_map.events[e[:id]]
          next unless ev
          ev.instance_variable_set(:@x, e[:x])
          ev.instance_variable_set(:@y, e[:y])
          ev.instance_variable_set(:@real_x, e[:real_x])
          ev.instance_variable_set(:@real_y, e[:real_y])
          ev.instance_variable_set(:@direction, e[:dir]) if [2, 4, 6, 8].include?(e[:dir])
          if ev.respond_to?(:battler) && ev.battler && ev.battler.respond_to?(:hp=)
            ev.battler.hp = e[:hp] if ev.battler.hp != e[:hp]
          end
          if e[:erased] && !ev.instance_variable_get(:@erased)
            ev.erase
          end
        end
      end
    end
  end

  #----------------------------------------------------------------------------
  # Hook Scene_Title: Auto-join (if configured) or press F7 to join Coop
  #----------------------------------------------------------------------------
  class Scene_Title
    alias maruchi_coop_title_start start
    def start
      maruchi_coop_title_start
      @maruchi_auto_triggered = false
      if Maruchi::Config::AUTO_JOIN
        @maruchi_auto_triggered = true
        Maruchi::Coop.connect_and_join
      end
    end

    alias maruchi_coop_title_update update
    def update
      maruchi_coop_title_update
      if Input.trigger?(Input::F7)
        Maruchi::Coop.connect_and_join
      end
      Maruchi::Coop.update
    end
  end

  #----------------------------------------------------------------------------
  # Hook Scene_Map: Tick networking & allow F7 connect/reconnect
  #----------------------------------------------------------------------------
  class Scene_Map
    alias maruchi_coop_map_start start
    def start
      maruchi_coop_map_start
      Maruchi::Log.info("Scene_Map started (map_id=#{$game_map ? $game_map.map_id : 'nil'}, coop_active=#{Maruchi::Coop.active?}, net_state=#{Maruchi::Net.state})")
    end

    alias maruchi_coop_map_update update
    def update
      if Input.trigger?(Input::F7)
        Maruchi::Coop.connect_and_join
      end
      Maruchi::Coop.update
      maruchi_coop_map_update
    end
  end

  #----------------------------------------------------------------------------
  # Hook Spriteset_Map: Render remote players, name tags, and status HUD
  #----------------------------------------------------------------------------
  class Spriteset_Map
    alias maruchi_coop_create_characters create_characters
    def create_characters
      maruchi_coop_create_characters
      @maruchi_remote_sprites = {}
      @maruchi_remote_tags    = {}
      @maruchi_hud = Sprite_MaruchiHud.new(@viewport3)
    end

    alias maruchi_coop_update_characters update_characters
    def update_characters
      maruchi_coop_update_characters
      update_maruchi_remote_sprites
      @maruchi_hud.update if @maruchi_hud
    end

    def update_maruchi_remote_sprites
      return unless @maruchi_remote_sprites
      begin
        remotes = Maruchi::Coop.remote_players

        # Add sprites for new remote players
        remotes.each do |pid, rp|
          unless @maruchi_remote_sprites[pid]
            @maruchi_remote_sprites[pid] = Sprite_Character.new(@viewport1, rp)
            @maruchi_remote_tags[pid]    = Sprite_RemoteNameTag.new(@viewport1, rp)
            Maruchi::Log.info("Created Sprite_Character for remote player ##{pid}")
          end
        end

        # Remove sprites for departed remote players
        @maruchi_remote_sprites.keys.each do |pid|
          unless remotes[pid]
            sp = @maruchi_remote_sprites.delete(pid)
            tg = @maruchi_remote_tags.delete(pid)
            sp.dispose if sp && !sp.disposed?
            tg.dispose if tg && !tg.disposed?
          end
        end

        @maruchi_remote_sprites.each_value { |sp| sp.update }
        @maruchi_remote_tags.each_value    { |tg| tg.update }
      rescue Exception => e
        Maruchi::Log.error("Remote sprite error: #{e.class}: #{e.message} (#{(e.backtrace || [])[0]})")
      end
    end

    alias maruchi_coop_dispose_characters dispose_characters
    def dispose_characters
      if @maruchi_remote_sprites
        @maruchi_remote_sprites.each_value { |sp| sp.dispose if sp && !sp.disposed? }
        @maruchi_remote_sprites.clear
      end
      if @maruchi_remote_tags
        @maruchi_remote_tags.each_value { |tg| tg.dispose if tg && !tg.disposed? }
        @maruchi_remote_tags.clear
      end
      if @maruchi_hud
        @maruchi_hud.dispose unless @maruchi_hud.disposed?
        @maruchi_hud = nil
      end
      maruchi_coop_dispose_characters
    end
  end

  #----------------------------------------------------------------------------
  # Hook Game_Event: Suppress local autonomous movement for server-synced enemies
  #----------------------------------------------------------------------------
  class Game_Event
    alias maruchi_coop_update_self_movement update_self_movement
    def update_self_movement
      if Maruchi::Coop.connected? && respond_to?(:battler) && battler.is_a?(Game_Enemy)
        return
      end
      maruchi_coop_update_self_movement
    end
  end

  #----------------------------------------------------------------------------
  # Hook Game_Player#shoot: Forward XAS weapon shots to authoritative server
  #----------------------------------------------------------------------------
  class Game_Player
    if method_defined?(:shoot)
      alias maruchi_coop_shoot shoot
      def shoot(action_id)
        if Maruchi::Coop.connected? && action_id.to_i > 0
          Maruchi::Coop.send_action("SHOOT", action_id.to_i, @direction)
        end
        maruchi_coop_shoot(action_id)
      end
    end
  end
end
