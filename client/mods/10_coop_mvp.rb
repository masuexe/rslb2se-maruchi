#==============================================================================
# Maruchi Co-op / PvP Client (Step 4.3: Transfers, World Sync, Char & Mode)
# Strictly Ruby 1.8.1 / RGSS2 compatible
# - Press F7 on Title or Map to connect/join the headless server (or AUTO_JOIN=1)
# - Press F8 on Map to open the Multiplayer Lobby Menu (Actor / Map / Mode)
# - Renders remote players with smooth interpolation, action poses, name & HP bars
# - Renders server-authoritative projectiles (Token_Bullet) & item drops (treasure)
# - Syncs authoritative HP/MP, combat FX, knockback, down/revive, switches & maps
#==============================================================================
if Maruchi::Config::MODS[:coop_client]

  #----------------------------------------------------------------------------
  # Lightweight Battler proxy for Remote Players so native Sprite_Character
  # can display damage popups & item pickup text seamlessly
  #----------------------------------------------------------------------------
  class Maruchi_RemoteBattler
    attr_accessor :hp, :maxhp, :mp, :maxmp
    attr_accessor :damage, :damage_pop, :damage_type, :critical
    attr_accessor :no_damage_pop, :defeated, :breath_effect

    def initialize
      @hp = 100
      @maxhp = 100
      @mp = 100
      @maxmp = 100
      @damage = nil
      @damage_pop = false
      @damage_type = ""
      @critical = false
      @no_damage_pop = false
      @defeated = false
      @breath_effect = false
    end

    def dead?
      @hp <= 0
    end
  end

  #----------------------------------------------------------------------------
  # Remote player entity rendered by Sprite_Character on Spriteset_Map
  #----------------------------------------------------------------------------
  class Game_RemotePlayer < Game_Character
    attr_accessor :player_id, :player_name, :actor_id, :team
    attr_accessor :hp, :maxhp, :mp, :maxmp, :down_timer
    attr_accessor :target_real_x, :target_real_y, :remote_moving
    attr_accessor :remote_pattern, :remote_step_anime
    attr_accessor :erased, :can_update, :throw_active, :battler

    def initialize(player_id, name)
      super()
      @player_id = player_id
      @player_name = name.to_s
      @actor_id = 1
      @team = 0
      @hp = 100
      @maxhp = 100
      @mp = 0
      @maxmp = 0
      @down_timer = 0
      @erased = false
      @can_update = true
      @throw_active = false
      @battler = Maruchi_RemoteBattler.new
      @through = true
      @walk_anime = true
      @step_anime = false
      @priority_type = 1
      @target_real_x = 0
      @target_real_y = 0
      @remote_moving = false
      @remote_pattern = 1
      @remote_step_anime = false
      @initialized_pos = false
    end

    def downed?
      @down_timer > 0
    end

    def apply_snapshot(p)
      @player_name = p[:name] if p[:name] && !p[:name].empty?
      @actor_id    = p[:actor_id]
      @team        = p[:team]
      @hp          = p[:hp]
      @maxhp       = [p[:maxhp].to_i, 1].max
      @mp          = p[:mp].to_i
      @maxmp       = p[:maxmp].to_i
      @down_timer  = p[:down_timer].to_i
      @battler.hp    = @hp
      @battler.maxhp = @maxhp
      @battler.mp    = @mp
      @battler.maxmp = @maxmp
      @opacity       = (@down_timer > 0) ? 128 : 255
      @direction   = p[:dir] if [2, 4, 6, 8].include?(p[:dir])
      @x           = p[:x]
      @y           = p[:y]
      @target_real_x = p[:real_x]
      @target_real_y = p[:real_y]
      @remote_moving = p[:moving]
      @remote_pattern = p[:pattern] if p[:pattern]
      @remote_step_anime = !!p[:step_anime]

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
      dx = @target_real_x - @real_x
      dy = @target_real_y - @real_y
      if dx.abs > 1024 || dy.abs > 1024
        @real_x = @target_real_x
        @real_y = @target_real_y
      else
        @real_x += (dx / 2)
        @real_y += (dy / 2)
        @real_x = @target_real_x if dx.abs < 4
        @real_y = @target_real_y if dy.abs < 4
      end

      if @down_timer > 0
        @step_anime = false
        @pattern = @original_pattern
        @anime_count = 0
      elsif @remote_step_anime
        @step_anime = true
        @pattern = @remote_pattern
        @anime_count = 0
      elsif @remote_moving || dx.abs > 8 || dy.abs > 8
        @step_anime = false
        @anime_count += 1.5
        if @anime_count >= 12
          @pattern = (@pattern + 1) % 4
          @anime_count = 0
        end
      else
        @step_anime = false
        @pattern = @original_pattern
        @anime_count = 0
      end
    end
  end

  #----------------------------------------------------------------------------
  # Authoritative server Token_Event proxy (Projectiles & Dropped Treasures)
  #----------------------------------------------------------------------------
  class Game_RemoteToken < Game_Character
    attr_accessor :token_id, :token_kind
    attr_accessor :target_real_x, :target_real_y, :remote_jump_y
    attr_accessor :erased, :can_update, :throw_active, :battler

    def initialize(token_id)
      super()
      @token_id = token_id
      @token_kind = 0
      @erased = false
      @can_update = true
      @throw_active = false
      @battler = nil
      @through = true
      @priority_type = 1
      @target_real_x = 0
      @target_real_y = 0
      @remote_jump_y = 0
      @initialized_pos = false
      @tool_id = 0
      @tool_effect = ""
      @icon_name = nil
      @treasure = nil
      @treasure_time = 0
      @treasure_float = [0, 0, 0, 0]
      @temp_id = 0
      @collapse_duration = 0
      @knock_back_duration = nil
    end

    def apply_snapshot(t)
      @token_kind = t[:kind]
      @x = t[:x]
      @y = t[:y]
      @target_real_x = t[:real_x]
      @target_real_y = t[:real_y]
      @direction = t[:dir] if [2, 4, 6, 8].include?(t[:dir])
      @character_name = t[:char_name] || ""
      @character_index = t[:char_index].to_i
      @pattern = t[:pattern].to_i
      @opacity = t[:opacity].to_i
      @blend_type = t[:blend_type].to_i
      @angle = t[:angle].to_f
      @zoom_x = t[:zoom_x].to_f / 100.0
      @zoom_y = t[:zoom_y].to_f / 100.0
      @icon_name = t[:icon_name]
      @remote_jump_y = t[:jump_y].to_i
      @priority_type = (@token_kind == 1) ? 1 : 2

      unless @initialized_pos
        @real_x = @target_real_x
        @real_y = @target_real_y
        @initialized_pos = true
      end
    end

    def screen_y
      super - @remote_jump_y
    end

    def update
      dx = @target_real_x - @real_x
      dy = @target_real_y - @real_y
      if dx.abs > 1024 || dy.abs > 1024
        @real_x = @target_real_x
        @real_y = @target_real_y
      else
        @real_x += (dx / 2)
        @real_y += (dy / 2)
        @real_x = @target_real_x if dx.abs < 4
        @real_y = @target_real_y if dy.abs < 4
      end
    end
  end

  #----------------------------------------------------------------------------
  # Overhead Name Tag + Mini HP Bar / Down Timer for Remote Players
  #----------------------------------------------------------------------------
  class Sprite_RemoteNameTag < Sprite
    def initialize(viewport, character)
      super(viewport)
      @character = character
      @last_key = nil
      self.z = 210
      self.bitmap = Bitmap.new(128, 30)
      self.bitmap.font.size = 13
      self.bitmap.font.bold = true
      self.ox = 64
      self.oy = 62
      refresh_tag
      update
    end

    def refresh_tag
      down_sec = (@character.down_timer.to_i + 59) / 60
      key = [@character.player_name.to_s, @character.hp.to_i, @character.maxhp.to_i, down_sec, Maruchi::Coop.server_mode]
      return if key == @last_key
      @last_key = key

      self.bitmap.clear
      label = down_sec > 0 ? "#{@character.player_name} [DOWN #{down_sec}s]" : @character.player_name.to_s
      self.bitmap.font.color = Color.new(0, 0, 0, 210)
      self.bitmap.draw_text(1, 1, 128, 18, label, 1)
      if down_sec > 0
        self.bitmap.font.color = Color.new(255, 160, 80, 255)
      elsif Maruchi::Coop.server_mode == "pvp"
        self.bitmap.font.color = Color.new(255, 110, 110, 255)
      else
        self.bitmap.font.color = Color.new(120, 240, 255, 255)
      end
      self.bitmap.draw_text(0, 0, 128, 18, label, 1)

      bx = 40
      by = 20
      bw = 48
      bh = 5
      mhp = [@character.maxhp.to_i, 1].max
      hp  = [[@character.hp.to_i, 0].max, mhp].min
      fill_w = ((hp * (bw - 2)) / mhp).to_i
      self.bitmap.fill_rect(bx, by, bw, bh, Color.new(0, 0, 0, 200))
      self.bitmap.fill_rect(bx + 1, by + 1, bw - 2, bh - 2, Color.new(110, 20, 20, 220))
      if fill_w > 0
        bar_col = (hp * 3 < mhp) ? Color.new(255, 90, 60) : Color.new(80, 235, 120)
        self.bitmap.fill_rect(bx + 1, by + 1, fill_w, bh - 2, bar_col)
      end
    end

    def update
      super
      refresh_tag
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
  # Top-Right Multiplayer Status & Party HP/MP HUD
  #----------------------------------------------------------------------------
  class Sprite_MaruchiHud < Sprite
    HUD_W = 208
    ROW_H = 22
    MAX_ROWS = 6

    def initialize(viewport)
      super(viewport)
      self.z = 250
      self.x = 544 - HUD_W - 4
      self.y = 4
      self.bitmap = Bitmap.new(HUD_W, 24 + ROW_H * MAX_ROWS)
      @last_sig = nil
      update
    end

    def update
      super
      header = Maruchi::Coop.hud_text
      rows   = Maruchi::Coop.party_hud_rows
      sig = [header, rows]
      return if sig == @last_sig
      @last_sig = sig

      self.bitmap.clear
      self.bitmap.fill_rect(0, 0, HUD_W, 20, Color.new(0, 0, 0, 155))
      self.bitmap.font.size = 12
      self.bitmap.font.bold = true
      if Maruchi::Coop.connected?
        self.bitmap.font.color = (Maruchi::Coop.server_mode == "pvp") ? Color.new(255, 120, 120) : Color.new(120, 255, 160)
      else
        self.bitmap.font.color = Color.new(255, 220, 120)
      end
      self.bitmap.draw_text(4, 1, HUD_W - 8, 18, header, 2)

      return unless Maruchi::Coop.connected?

      y = 22
      rows[0, MAX_ROWS].each do |r|
        self.bitmap.fill_rect(0, y, HUD_W, ROW_H - 2, Color.new(0, 0, 0, 130))
        self.bitmap.font.size = 11
        self.bitmap.font.bold = r[:is_self]
        if r[:down_sec] > 0
          self.bitmap.font.color = Color.new(255, 150, 90)
          title = "#{r[:name]} DOWN #{r[:down_sec]}s"
        else
          self.bitmap.font.color = r[:is_self] ? Color.new(255, 240, 140) : Color.new(160, 235, 255)
          title = r[:name]
        end
        self.bitmap.draw_text(4, y, 102, 13, title, 0)

        self.bitmap.font.bold = false
        self.bitmap.font.color = Color.new(235, 235, 235)
        self.bitmap.draw_text(106, y, HUD_W - 110, 13, "#{r[:hp]}/#{r[:maxhp]}", 2)

        bar_y = y + 14
        hp_w = 132
        mhp = [r[:maxhp], 1].max
        hp_fill = [[(r[:hp] * hp_w) / mhp, 0].max, hp_w].min
        self.bitmap.fill_rect(4, bar_y, hp_w, 4, Color.new(90, 20, 20, 220))
        if hp_fill > 0
          col = (r[:hp] * 3 < mhp) ? Color.new(255, 85, 65) : Color.new(80, 230, 120)
          self.bitmap.fill_rect(4, bar_y, hp_fill, 4, col)
        end

        mp_x = 140
        mp_w = HUD_W - mp_x - 4
        mmp = [r[:maxmp], 1].max
        mp_fill = r[:maxmp] > 0 ? [[(r[:mp] * mp_w) / mmp, 0].max, mp_w].min : 0
        self.bitmap.fill_rect(mp_x, bar_y, mp_w, 4, Color.new(20, 35, 95, 220))
        self.bitmap.fill_rect(mp_x, bar_y, mp_fill, 4, Color.new(95, 185, 255)) if mp_fill > 0

        y += ROW_H
      end
    end

    def dispose
      self.bitmap.dispose if self.bitmap && !self.bitmap.disposed?
      super
    end
  end

  #----------------------------------------------------------------------------
  # Co-op / PvP Client Controller
  #----------------------------------------------------------------------------
  module Maruchi
    module Coop
      @active = false
      @hello_sent = false
      @welcomed = false
      @my_id = nil
      @my_hp = 100
      @my_maxhp = 100
      @my_mp = 0
      @my_maxmp = 0
      @my_down_timer = 0
      @server_map_id = nil
      @server_mode = "coop"
      @host_id = nil
      @cutscene_locked = false
      @synced_msg_seq = 0
      @pending_msg_close = false
      @pending_msg_show = nil
      @applying_server_map = false
      @remote_players = {}
      @remote_tokens  = {}
      @enemy_targets  = {}
      @seq = 0
      @send_tick = 0
      @ping_tick = 0
      @rtt_ms = nil
      @last_transfer_req_at = 0.0
      @last_transfer_req_map = nil
      @last_interact_req_at = 0.0
      @server_error_note = nil
      @last_state = Maruchi::Net::STATE_DISCONNECTED
      @status_note = "F7:Join  F8:Menu"

      def self.active?;              @active;              end
      def self.connected?;           @welcomed && Maruchi::Net.connected?; end
      def self.my_id;                @my_id;               end
      def self.host_id;              @host_id;             end
      def self.is_host?;             connected? && @my_id && @host_id && @my_id == @host_id; end
      def self.cutscene_locked?;     connected? && (@cutscene_locked || @synced_msg_seq > 0); end
      def self.synced_msg_seq;       @synced_msg_seq;      end
      def self.pending_msg_close?;   @pending_msg_close;   end
      def self.pending_msg_show;     @pending_msg_show;    end
      def self.server_mode;          @server_mode;         end
      def self.server_map_id;        @server_map_id;       end
      def self.my_downed?;           @my_down_timer > 0;   end
      def self.applying_server_map?; @applying_server_map; end
      def self.remote_players;       @remote_players;      end
      def self.remote_tokens;        @remote_tokens;       end

      def self.consume_pending_msg_close!
        @pending_msg_close = false
        @synced_msg_seq = 0
      end

      def self.consume_pending_msg_show!
        msg = @pending_msg_show
        @pending_msg_show = nil
        msg
      end

      def self.send_msg_ack(seq, choice_idx = -1)
        return unless connected? && is_host? && seq.to_i > 0
        Maruchi::Net.send_msg(Maruchi::Protocol.build_msg_ack(seq.to_i, choice_idx.to_i))
        @synced_msg_seq = 0 if @synced_msg_seq == seq.to_i
      end

      def self.hud_text
        if connected?
          cnt = @remote_players.size + 1
          ping_str = @rtt_ms ? " #{@rtt_ms}ms" : ""
          mode_tag = (@server_mode == "pvp") ? "PVP" : "COOP"
          host_mark = is_host? ? "*" : ""
          return "#{mode_tag} P##{@my_id}#{host_mark} (#{cnt}P)#{ping_str} [F8]"
        elsif @active && Maruchi::Net.connecting?
          return "COOP Connecting..."
        else
          return @status_note
        end
      end

      def self.party_hud_rows
        return [] unless connected?
        rows = []
        my_prefix = is_host? ? "[H] " : ""
        rows.push({
          :id       => @my_id.to_i,
          :name     => my_prefix + Maruchi::Config::PLAYER_NAME.to_s,
          :hp       => @my_hp.to_i,
          :maxhp    => [@my_maxhp.to_i, 1].max,
          :mp       => @my_mp.to_i,
          :maxmp    => @my_maxmp.to_i,
          :down_sec => (@my_down_timer.to_i + 59) / 60,
          :is_self  => true
        })
        @remote_players.keys.sort.each do |pid|
          rp = @remote_players[pid]
          r_prefix = (@host_id && pid == @host_id) ? "[H] " : ""
          rows.push({
            :id       => pid,
            :name     => r_prefix + rp.player_name.to_s,
            :hp       => rp.hp.to_i,
            :maxhp    => [rp.maxhp.to_i, 1].max,
            :mp       => rp.mp.to_i,
            :maxmp    => rp.maxmp.to_i,
            :down_sec => (rp.down_timer.to_i + 59) / 60,
            :is_self  => false
          })
        end
        rows
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
        @host_id = nil
        @cutscene_locked = false
        @synced_msg_seq = 0
        @pending_msg_close = false
        @pending_msg_show = nil
        @my_down_timer = 0
        @remote_players.clear
        @remote_tokens.clear
        @enemy_targets.clear
        @server_error_note = nil
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
        @host_id = nil
        @cutscene_locked = false
        @synced_msg_seq = 0
        @pending_msg_close = false
        @pending_msg_show = nil
        @my_down_timer = 0
        @remote_players.clear
        @remote_tokens.clear
        @enemy_targets.clear
        @status_note = "Offline (F7:Join)"
      end

      def self.ensure_map_scene_for_join(map_id, sx, sy, dir = 2)
        if $game_party && $game_party.members.empty?
          aid = Maruchi::Config::ACTOR_ID
          aid = 1 unless $data_actors && $data_actors[aid]
          $game_party.add_actor(aid)
        end

        same_map = ($game_map && $game_map.map_id == map_id && $scene.is_a?(Scene_Map))
        unless same_map
          @remote_tokens.clear
          @enemy_targets.clear
        end
        @applying_server_map = true
        begin
          if $game_map && $game_player
            $game_message.clear if $game_message
            $game_map.interpreter.clear if $game_map.interpreter
            if !same_map
              $game_map.clear_tokens if $game_map.respond_to?(:clear_tokens)
              $game_map.setup(map_id)
              $game_player.moveto(sx, sy)
              $game_player.direction = dir if [2, 4, 6, 8].include?(dir)
              $game_player.refresh
              $game_map.autoplay
              $scene = Scene_Map.new
            else
              $game_player.moveto(sx, sy)
              $game_player.direction = dir if [2, 4, 6, 8].include?(dir)
              $game_player.refresh
            end
            Maruchi::Log.info("Entered live #{@server_mode.upcase} Map ##{map_id} at (#{sx},#{sy}), actor=#{$game_party.members[0] ? $game_party.members[0].name : 'none'}")
          end
        ensure
          @applying_server_map = false
        end
      end

      def self.apply_local_actor_change(actor_id)
        return unless $game_party && $data_actors && $data_actors[actor_id]
        # Replace party leader with chosen actor cleanly
        $game_party.members.dup.each { |a| $game_party.remove_actor(a.id) }
        $game_party.add_actor(actor_id)
        if $game_party.members[0]
          $game_party.members[0].recover_all
        end
        if $game_player
          $game_player.refresh
          $game_player.need_refresh = true if $game_player.respond_to?(:need_refresh=)
        end
        Maruchi::Log.info("Switched local actor to ##{actor_id} (#{$data_actors[actor_id].name})")
      end

      def self.send_action(kind, action_id, dir, dir8 = 0)
        return unless connected?
        Maruchi::Net.send_msg(Maruchi::Protocol.build_action(kind, action_id, dir, dir8))
      end

      def self.request_actor(actor_id)
        return unless connected?
        Maruchi::Net.send_msg(Maruchi::Protocol.build_req_actor(actor_id))
      end

      def self.request_transfer(map_id, x = -1, y = -1, dir = 2)
        return unless connected?
        now = Time.now.to_f
        if @last_transfer_req_map == map_id.to_i && (now - @last_transfer_req_at) < 0.6
          return
        end
        @last_transfer_req_map = map_id.to_i
        @last_transfer_req_at  = now
        Maruchi::Net.send_msg(Maruchi::Protocol.build_req_transfer(map_id, x, y, dir))
      end

      def self.request_mode(mode)
        return unless connected?
        Maruchi::Net.send_msg(Maruchi::Protocol.build_req_mode(mode))
      end

      def self.request_interact
        return unless connected? && $game_player
        now = Time.now.to_f
        return if (now - @last_interact_req_at) < 0.25
        @last_interact_req_at = now
        Maruchi::Net.send_msg(Maruchi::Protocol.build_req_interact($game_player.x, $game_player.y, $game_player.direction))
      end

      def self.update
        return unless @active

        st = Maruchi::Net.state
        if st != @last_state
          @last_state = st
          if st == Maruchi::Net::STATE_ERROR
            err = Maruchi::Net.last_error
            @status_note = @server_error_note || "Err (F7 retry)"
            @welcomed = false
            Maruchi::Log.error("Network error: #{err}")
          elsif st == Maruchi::Net::STATE_DISCONNECTED
            @status_note = @server_error_note || "Disconnected (F7)"
            @welcomed = false
          end
        end

        if st == Maruchi::Net::STATE_CONNECTED && !@hello_sent
          aid = ($game_party && $game_party.members[0]) ? $game_party.members[0].id : Maruchi::Config::ACTOR_ID
          Maruchi::Net.send_msg(Maruchi::Protocol.build_hello(Maruchi::Config::PLAYER_NAME, aid))
          @hello_sent = true
          Maruchi::Log.info("Sent HELLO (name=#{Maruchi::Config::PLAYER_NAME}, actor=#{aid})")
        end

        Maruchi::Net.poll_all(128).each do |payload|
          handle_message(payload)
        end

        @remote_players.each_value { |rp| rp.update }
        @remote_tokens.each_value  { |tk| tk.update }
        update_enemy_interpolation if connected? && $scene.is_a?(Scene_Map) && $game_map

        if connected? && $game_player
          $game_player.opacity = (@my_down_timer > 0) ? 128 : 255
        end

        if connected? && $scene.is_a?(Scene_Map) && $game_player && $game_map
          @send_tick += 1
          if @send_tick >= 2
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
              0,
              $game_player.pattern,
              $game_player.step_anime
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
          dir = f.length > 4 ? f[4].to_i : 2
          @server_map_id = mid
          ensure_map_scene_for_join(mid, sx, sy, dir)

        when "WORLD_SYNC"
          ws = Maruchi::Protocol.parse_world_sync(f[1], f[2], f[3])
          if $game_switches
            ws[:switches].each { |sid| $game_switches[sid] = true }
          end
          if $game_variables
            ws[:variables].each { |pair| $game_variables[pair[0]] = pair[1] }
          end
          if $game_self_switches
            ws[:self_switches].each { |e| $game_self_switches[[e[0], e[1], e[2]]] = e[3] }
          end
          $game_map.need_refresh = true if $game_map

        when "SNAP"
          return unless @welcomed && @my_id
          snap_map = f[2].to_i
          players  = Maruchi::Protocol.parse_snapshot_players(f[3])
          enemies  = Maruchi::Protocol.parse_snapshot_enemies(f[4])
          tokens   = (f.length > 5) ? Maruchi::Protocol.parse_snapshot_tokens(f[5]) : []

          seen_ids = {}
          players.each do |p|
            pid = p[:id]
            if pid == @my_id
              apply_local_player_snapshot(p)
              next
            end
            seen_ids[pid] = true
            rp = @remote_players[pid]
            if rp.nil?
              rp = Game_RemotePlayer.new(pid, p[:name])
              @remote_players[pid] = rp
              Maruchi::Log.info("Spawned remote player ##{pid} '#{p[:name]}' at (#{p[:x]},#{p[:y]})")
            end
            rp.apply_snapshot(p)
          end
          @remote_players.keys.each do |pid|
            unless seen_ids[pid]
              @remote_players.delete(pid)
              Maruchi::Log.info("Removed remote player ##{pid}")
            end
          end

          if $scene.is_a?(Scene_Map) && $game_map && $game_map.map_id == snap_map
            apply_enemy_snapshots(enemies)
            apply_token_snapshots(tokens)
          end

        when "EVENT"
          handle_server_event(f)

        when "PONG"
          sent_ms = f[1].to_i
          now_ms  = (Time.now.to_f * 1000.0).to_i
          rtt = now_ms - sent_ms
          @rtt_ms = rtt if rtt >= 0 && rtt < 10000
        end
      end

      def self.apply_local_player_snapshot(p)
        @my_hp         = p[:hp].to_i
        @my_maxhp      = [p[:maxhp].to_i, 1].max
        @my_mp         = p[:mp].to_i
        @my_maxmp      = p[:maxmp].to_i
        @my_down_timer = p[:down_timer].to_i

        if $game_party && $game_party.members[0]
          actor = $game_party.members[0]
          display_hp = (@my_down_timer > 0) ? 0 : @my_hp
          actor.hp = display_hp if actor.hp != display_hp
          actor.mp = @my_mp if actor.mp != @my_mp
        end
      end

      def self.find_fx_target(t_type, t_id)
        case t_type
        when "P"
          return $game_player if t_id == @my_id
          return @remote_players[t_id]
        when "E"
          return ($game_map ? $game_map.events[t_id] : nil)
        when "T"
          return @remote_tokens[t_id]
        end
        nil
      end

      def self.handle_server_event(f)
        kind = Maruchi::Protocol.unesc(f[1])
        case kind
        when "HOST_CHANGE"
          @host_id = f[2].to_i
          Maruchi::Log.info("Room host is now P##{@host_id} (is_host=#{is_host?})")

        when "CUTSCENE"
          @cutscene_locked = (f[2].to_i != 0)
          Maruchi::Log.info("Cutscene lock -> #{@cutscene_locked}")

        when "MSG_SHOW"
          seq        = f[2].to_i
          face_name  = Maruchi::Protocol.unesc(f[3])
          face_index = f[4].to_i
          bg         = f[5].to_i
          pos        = f[6].to_i
          c_start    = f[7].to_i
          c_max      = f[8].to_i
          c_cancel   = f[9].to_i
          raw_texts  = Maruchi::Protocol.unesc(f[10])
          lines      = raw_texts.empty? ? [] : raw_texts.split(";", -1).collect { |s| Maruchi::Protocol.unesc(s) }
          @synced_msg_seq = seq
          @pending_msg_close = false
          @pending_msg_show = {
            :seq          => seq,
            :face_name    => face_name,
            :face_index   => face_index,
            :background   => bg,
            :position     => pos,
            :choice_start => c_start,
            :choice_max   => c_max,
            :choice_cancel => c_cancel,
            :texts        => lines
          }

        when "MSG_CLOSE"
          seq = f[2].to_i
          if @synced_msg_seq == 0 || @synced_msg_seq == seq
            @pending_msg_show = nil
            @pending_msg_close = true
          end

        when "FX_BGM"
          bgm_name = Maruchi::Protocol.unesc(f[2])
          vol      = f[3].to_i
          pitch    = f[4].to_i
          begin
            Audio.bgm_play(bgm_name, vol > 0 ? vol : 80, pitch > 0 ? pitch : 100)
          rescue Exception
          end

        when "FX_BGM_STOP"
          begin
            Audio.bgm_stop
          rescue Exception
          end

        when "SW_SET"
          sid = f[2].to_i
          val = (f[3].to_i != 0)
          if $game_switches && sid > 0
            $game_switches[sid] = val
            $game_map.need_refresh = true if $game_map
          end

        when "VAR_SET"
          vid = f[2].to_i
          val = f[3].to_i
          if $game_variables && vid > 0
            $game_variables[vid] = val
            $game_map.need_refresh = true if $game_map
          end

        when "SSW_SET"
          mid = f[2].to_i
          eid = f[3].to_i
          ch  = Maruchi::Protocol.unesc(f[4])
          val = (f[5].to_i != 0)
          if $game_self_switches
            $game_self_switches[[mid, eid, ch]] = val
            $game_map.need_refresh = true if $game_map
          end

        when "MODE_CHANGE"
          @server_mode = Maruchi::Protocol.unesc(f[2])
          Maruchi::Log.info("Room mode changed to #{@server_mode.upcase}")
          if $game_player && $game_player.battler
            $game_player.battler.damage = @server_mode.upcase + " MODE!"
            $game_player.battler.damage_pop = true
          end

        when "ACTOR_CHANGED"
          pid   = f[2].to_i
          aid   = f[3].to_i
          aname = Maruchi::Protocol.unesc(f[4])
          if pid == @my_id
            apply_local_actor_change(aid)
            if $game_player && $game_player.battler
              $game_player.battler.damage = aname
              $game_player.battler.damage_pop = true
            end
          elsif @remote_players[pid]
            rp = @remote_players[pid]
            if rp.battler
              rp.battler.damage = aname
              rp.battler.damage_pop = true
            end
          end

        when "FX_ANI"
          t_type  = Maruchi::Protocol.unesc(f[2])
          t_id    = f[3].to_i
          anim_id = f[4].to_i
          return if anim_id <= 0
          target = find_fx_target(t_type, t_id)
          target.animation_id = anim_id if target

        when "FX_DMG"
          t_type   = Maruchi::Protocol.unesc(f[2])
          t_id     = f[3].to_i
          dmg_str  = Maruchi::Protocol.unesc(f[4])
          dmg_type = Maruchi::Protocol.unesc(f[5])
          crit     = (f[6].to_i != 0)
          target = find_fx_target(t_type, t_id)
          if target && target.respond_to?(:battler) && target.battler
            b = target.battler
            val = (dmg_str =~ /\A-?\d+\z/) ? dmg_str.to_i : dmg_str
            b.damage      = val
            b.damage_type = dmg_type
            b.critical    = crit if b.respond_to?(:critical=)
            b.damage_pop  = true
          end

        when "FX_SE"
          se_name = Maruchi::Protocol.unesc(f[2])
          vol     = f[3].to_i
          pitch   = f[4].to_i
          begin
            Audio.se_play(se_name, vol > 0 ? vol : 80, pitch > 0 ? pitch : 100)
          rescue Exception
          end

        when "KNOCKBACK"
          pid   = f[2].to_i
          dir   = f[3].to_i
          power = f[4].to_i
          if pid == @my_id && $game_player && $game_player.respond_to?(:blow)
            $game_player.blow(dir, power)
          end

        when "PLAYER_DOWN"
          pid = f[2].to_i
          timer = f[3].to_i
          Sound.play_actor_collapse rescue nil
          if pid == @my_id
            @my_down_timer = timer > 0 ? timer : 300
            if $game_player && $game_player.battler
              $game_player.battler.damage = "DOWN!"
              $game_player.battler.damage_pop = true
            end
          elsif @remote_players[pid]
            rp = @remote_players[pid]
            rp.down_timer = timer > 0 ? timer : 300
            if rp.battler
              rp.battler.damage = "DOWN!"
              rp.battler.damage_pop = true
            end
          end

        when "PLAYER_REVIVE"
          pid = f[2].to_i
          rx  = f[3].to_i
          ry  = f[4].to_i
          Sound.play_recovery rescue nil
          if pid == @my_id && $game_player
            @my_down_timer = 0
            $game_player.opacity = 255
            if $game_party && $game_party.members[0]
              $game_party.members[0].recover_all
              $game_player.battler.damage = "REVIVED!"
              $game_player.battler.damage_pop = true
            end
            if $game_player.x != rx || $game_player.y != ry
              $game_player.moveto(rx, ry)
            end
          elsif @remote_players[pid]
            rp = @remote_players[pid]
            rp.down_timer = 0
            rp.opacity = 255
            if rp.battler
              rp.battler.damage = "REVIVED!"
              rp.battler.damage_pop = true
            end
          end

        when "ENEMY_DEAD"
          ev_id    = f[2].to_i
          enemy_id = f[3].to_i
          exp      = f[4].to_i
          gold     = f[5].to_i
          handle_enemy_dead(ev_id, enemy_id, exp, gold)

        when "PICKUP"
          picker_id = f[2].to_i
          tr_kind   = f[3].to_i
          tr_id     = f[4].to_i
          handle_treasure_pickup(picker_id, tr_kind, tr_id)

        when "ERROR"
          code = Maruchi::Protocol.unesc(f[2])
          msg  = f.length > 3 ? Maruchi::Protocol.unesc(f[3]) : code
          @server_error_note = (code == "VERSION_MISMATCH") ? "Ver mismatch!" : "Err: #{code}"
          @status_note = @server_error_note
          Maruchi::Log.error("Server ERROR [#{code}]: #{msg}")

        when "JOIN", "LEAVE"
          Maruchi::Log.info("Server EVENT: #{kind} #{f[2..-1].inspect}")
        end
      end

      def self.handle_enemy_dead(ev_id, enemy_id, exp, gold)
        Sound.play_enemy_collapse rescue nil

        if $game_map && $game_map.events[ev_id]
          ev = $game_map.events[ev_id]
          if ev.respond_to?(:battler) && ev.battler
            ev.battler.hp = 0
            ev.battler.defeated = true if ev.battler.respond_to?(:defeated=)
          end
          ev.through = true
          ev.collapse_duration = 60 if ev.respond_to?(:collapse_duration=)
          if $data_enemies && $data_enemies[enemy_id]
            en = $data_enemies[enemy_id]
            if en.note =~ /<Defeated Ani = (\d+)>/
              ev.animation_id = $1.to_i
            end
          end
        end

        if $game_variables
          $game_variables[6] = $game_variables[6].to_i + 1
          $game_variables[39] = $game_variables[39].to_i + 1
        end
        if $game_party && !$game_party.members.empty?
          if exp > 0
            case ($game_variables ? $game_variables[37].to_i : 0)
            when 0
              $game_party.members[0].gain_exp(exp, false)
            when 1
              $game_party.members.each { |a| a.gain_exp(exp, false) }
            when 2
              share = exp / [$game_party.members.size, 1].max
              $game_party.members.each { |a| a.gain_exp(share, false) }
            end
          end
          $game_party.gain_gold(gold) if gold > 0
        end
      end

      def self.handle_treasure_pickup(picker_id, tr_kind, tr_id)
        item = case tr_kind
               when 1 then ($data_items ? $data_items[tr_id] : nil)
               when 2 then ($data_weapons ? $data_weapons[tr_id] : nil)
               when 3 then ($data_armors ? $data_armors[tr_id] : nil)
               else nil
               end
        return unless item

        if picker_id == @my_id && $game_player && $game_party
          name_pop = true
          case tr_kind
          when 1
            if $game_player.respond_to?(:can_execute_field_item_effect?) && $game_player.can_execute_field_item_effect?(item)
              name_pop = false
            else
              $game_party.gain_item(item, 1)
            end
            $game_map.need_refresh = true if $game_map
          when 2
            $game_party.gain_item(item, 1, false)
          when 3
            $game_party.gain_item(item, 1, false)
          end
          if item.note =~ /<Drop Ani = (\d+)>/
            $game_player.animation_id = $1.to_i
          end
          if defined?(XAS_DAMAGE_POP) && XAS_DAMAGE_POP::DAMAGE_ITEM_POP && name_pop && $game_player.battler
            $game_player.battler.damage = item.name.to_s
            $game_player.battler.damage_pop = true
            $game_player.battler.damage_type = "Item"
          end
        else
          rp = @remote_players[picker_id]
          if rp
            if item.note =~ /<Drop Ani = (\d+)>/
              rp.animation_id = $1.to_i
            end
            if rp.battler
              rp.battler.damage = item.name.to_s
              rp.battler.damage_pop = true
              rp.battler.damage_type = "Item"
            end
          end
        end
      end

      def self.apply_enemy_snapshots(enemies)
        enemies.each do |e|
          ev = $game_map.events[e[:id]]
          next unless ev
          ev.instance_variable_set(:@x, e[:x])
          ev.instance_variable_set(:@y, e[:y])
          ev.instance_variable_set(:@direction, e[:dir]) if [2, 4, 6, 8].include?(e[:dir])

          prev = @enemy_targets[e[:id]]
          if prev.nil? || (e[:real_x] - ev.real_x).abs > 1024 || (e[:real_y] - ev.real_y).abs > 1024
            ev.instance_variable_set(:@real_x, e[:real_x])
            ev.instance_variable_set(:@real_y, e[:real_y])
          end
          @enemy_targets[e[:id]] = [e[:real_x], e[:real_y]]

          if ev.respond_to?(:battler) && ev.battler && ev.battler.respond_to?(:hp=)
            ev.battler.hp = e[:hp] if ev.battler.hp != e[:hp]
            if e[:defeated] && ev.battler.respond_to?(:defeated=)
              ev.battler.defeated = true
            end
          end
          if e[:erased] && !ev.instance_variable_get(:@erased)
            ev.erase
          end
        end
      end

      def self.update_enemy_interpolation
        @enemy_targets.each do |ev_id, pos|
          ev = $game_map.events[ev_id]
          next unless ev && !ev.erased
          rx = ev.real_x
          ry = ev.real_y
          dx = pos[0] - rx
          dy = pos[1] - ry
          next if dx == 0 && dy == 0
          nx = (dx.abs < 4) ? pos[0] : (rx + (dx / 2))
          ny = (dy.abs < 4) ? pos[1] : (ry + (dy / 2))
          ev.instance_variable_set(:@real_x, nx)
          ev.instance_variable_set(:@real_y, ny)
        end
      end

      def self.apply_token_snapshots(tokens)
        seen = {}
        tokens.each do |t|
          tid = t[:id]
          seen[tid] = true
          rt = @remote_tokens[tid]
          if rt.nil?
            rt = Game_RemoteToken.new(tid)
            @remote_tokens[tid] = rt
          end
          rt.apply_snapshot(t)
        end
        @remote_tokens.keys.each do |tid|
          @remote_tokens.delete(tid) unless seen[tid]
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
      if Maruchi::Config::AUTO_JOIN
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
  # Hook Scene_Map: Tick networking, F7 join, F8 Lobby Menu
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
      if Input.trigger?(Input::F8) && defined?(Scene_MaruchiMenu)
        Sound.play_decision rescue nil
        $scene = Scene_MaruchiMenu.new
        return
      end
      Maruchi::Coop.update
      maruchi_coop_map_update
    end
  end

  #----------------------------------------------------------------------------
  # Hook Sprite_Character: Protect enemy HP meter plugin (180) from proxies
  #----------------------------------------------------------------------------
  class Sprite_Character < Sprite_Base
    if method_defined?(:update_battler_meter)
      alias maruchi_coop_update_battler_meter update_battler_meter
      def update_battler_meter
        return if @character.is_a?(Game_RemotePlayer) || @character.is_a?(Game_RemoteToken)
        maruchi_coop_update_battler_meter
      end
    end
  end

  #----------------------------------------------------------------------------
  # Hook Spriteset_Map: Render remote players, remote tokens, name tags & HUD
  #----------------------------------------------------------------------------
  class Spriteset_Map
    alias maruchi_coop_create_characters create_characters
    def create_characters
      maruchi_coop_create_characters
      @maruchi_remote_sprites = {}
      @maruchi_remote_tags    = {}
      @maruchi_token_sprites  = {}
      @maruchi_hud = Sprite_MaruchiHud.new(@viewport3)
    end

    alias maruchi_coop_update_characters update_characters
    def update_characters
      maruchi_coop_update_characters
      update_maruchi_remote_sprites
      update_maruchi_token_sprites
      @maruchi_hud.update if @maruchi_hud
    end

    def update_maruchi_remote_sprites
      return unless @maruchi_remote_sprites
      begin
        remotes = Maruchi::Coop.remote_players

        remotes.each do |pid, rp|
          unless @maruchi_remote_sprites[pid]
            @maruchi_remote_sprites[pid] = Sprite_Character.new(@viewport1, rp)
            @maruchi_remote_tags[pid]    = Sprite_RemoteNameTag.new(@viewport1, rp)
            Maruchi::Log.info("Created Sprite_Character for remote player ##{pid}")
          end
        end

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

    def update_maruchi_token_sprites
      return unless @maruchi_token_sprites
      begin
        tokens = Maruchi::Coop.remote_tokens

        tokens.each do |tid, tk|
          unless @maruchi_token_sprites[tid]
            @maruchi_token_sprites[tid] = Sprite_Character.new(@viewport1, tk)
          end
        end

        @maruchi_token_sprites.keys.each do |tid|
          unless tokens[tid]
            sp = @maruchi_token_sprites.delete(tid)
            sp.dispose if sp && !sp.disposed?
          end
        end

        @maruchi_token_sprites.each_value { |sp| sp.update }
      rescue Exception => e
        Maruchi::Log.error("Remote token sprite error: #{e.class}: #{e.message} (#{(e.backtrace || [])[0]})")
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
      if @maruchi_token_sprites
        @maruchi_token_sprites.each_value { |sp| sp.dispose if sp && !sp.disposed? }
        @maruchi_token_sprites.clear
      end
      if @maruchi_hud
        @maruchi_hud.dispose unless @maruchi_hud.disposed?
        @maruchi_hud = nil
      end
      maruchi_coop_dispose_characters
    end
  end

  #----------------------------------------------------------------------------
  # Hook Window_Message: Host-driven synchronized cutscene dialogue & choices
  # - Server drives $game_message; all clients display identical text/portrait
  # - Only the room host can advance/close synced dialogue or pick choices
  # - Non-host clients stay in sync and close/advance immediately on server cue
  #----------------------------------------------------------------------------
  class Window_Message < Window_Selectable
    alias maruchi_coop_msg_update update
    def update
      if Maruchi::Coop.connected?
        if Maruchi::Coop.pending_msg_close?
          Maruchi::Coop.consume_pending_msg_close!
          if $game_message && $game_message.visible
            maruchi_force_close_message
          elsif $game_message && $game_message.busy
            $game_message.clear
          end
        end

        new_msg = Maruchi::Coop.consume_pending_msg_show!
        if new_msg && $game_message
          # Close any stale message cleanly before loading the authoritative one
          if $game_message.visible || $game_message.busy
            maruchi_force_close_message
          end
          $game_message.clear
          $game_message.face_name          = new_msg[:face_name]
          $game_message.face_index         = new_msg[:face_index]
          $game_message.background         = new_msg[:background]
          $game_message.position           = new_msg[:position]
          $game_message.choice_start       = new_msg[:choice_start]
          $game_message.choice_max         = new_msg[:choice_max]
          $game_message.choice_cancel_type = new_msg[:choice_cancel]
          new_msg[:texts].each { |ln| $game_message.texts.push(ln) }
          @maruchi_synced_seq = new_msg[:seq]
        end
      end
      maruchi_coop_msg_update
    end

    def maruchi_force_close_message
      @maruchi_forcing_close = true
      begin
        terminate_message
        @text = nil
        @wait_count = 0
        @opening = false
        @closing = false
      ensure
        @maruchi_forcing_close = false
        @maruchi_synced_seq = 0
      end
    end

    alias maruchi_coop_input_pause input_pause
    def input_pause
      if Maruchi::Coop.connected? && @maruchi_synced_seq.to_i > 0
        if Input.trigger?(Input::B) || Input.trigger?(Input::C)
          if @text != nil && !@text.empty?
            # Multi-page single message: allow local page flip within same message
            self.pause = false
            new_page if @line_count >= MAX_LINE
          elsif Maruchi::Coop.is_host?
            # Host advances the authoritative server message
            seq = @maruchi_synced_seq
            @maruchi_synced_seq = 0
            self.pause = false
            terminate_message
            Maruchi::Coop.send_msg_ack(seq, -1)
          end
        end
        return
      end
      maruchi_coop_input_pause
    end

    alias maruchi_coop_input_choice input_choice
    def input_choice
      if Maruchi::Coop.connected? && @maruchi_synced_seq.to_i > 0
        # Non-host waits for host's choice
        return unless Maruchi::Coop.is_host?
        if Input.trigger?(Input::B)
          if $game_message.choice_cancel_type > 0
            Sound.play_cancel
            seq = @maruchi_synced_seq
            choice_idx = $game_message.choice_cancel_type - 1
            @maruchi_synced_seq = 0
            terminate_message
            Maruchi::Coop.send_msg_ack(seq, choice_idx)
          end
        elsif Input.trigger?(Input::C)
          Sound.play_decision
          seq = @maruchi_synced_seq
          choice_idx = self.index
          @maruchi_synced_seq = 0
          terminate_message
          Maruchi::Coop.send_msg_ack(seq, choice_idx)
        end
        return
      end
      maruchi_coop_input_choice
    end

    alias maruchi_coop_terminate_message terminate_message
    def terminate_message
      # Handle \^ (@pause_skip) auto-advancing synced messages from host
      if !@maruchi_forcing_close && Maruchi::Coop.connected? && @maruchi_synced_seq.to_i > 0
        if Maruchi::Coop.is_host?
          seq = @maruchi_synced_seq
          @maruchi_synced_seq = 0
          maruchi_coop_terminate_message
          Maruchi::Coop.send_msg_ack(seq, -1)
          return
        end
      end
      maruchi_coop_terminate_message
    end
  end

  #----------------------------------------------------------------------------
  # Hook Game_Event: Suppress local AI, autorun cutscenes, enemy hits & defeat
  #----------------------------------------------------------------------------
  class Game_Event
    if method_defined?(:check_event_trigger_auto)
      alias maruchi_coop_check_event_trigger_auto check_event_trigger_auto
      def check_event_trigger_auto
        # Autorun (trigger == 3) cutscenes run authoritatively on server and stream to all clients
        return if Maruchi::Coop.connected?
        maruchi_coop_check_event_trigger_auto
      end
    end

    alias maruchi_coop_update_self_movement update_self_movement
    def update_self_movement
      if Maruchi::Coop.connected? && respond_to?(:battler) && battler.is_a?(Game_Enemy)
        return
      end
      maruchi_coop_update_self_movement
    end

    if method_defined?(:action_effect)
      alias maruchi_coop_event_action_effect action_effect
      def action_effect(bullet, action_id)
        if Maruchi::Coop.connected? && respond_to?(:battler) && battler.is_a?(Game_Enemy)
          return false
        end
        maruchi_coop_event_action_effect(bullet, action_id)
      end
    end

    if method_defined?(:execute_enemy_defeated_process)
      alias maruchi_coop_enemy_defeated execute_enemy_defeated_process
      def execute_enemy_defeated_process
        return if Maruchi::Coop.connected?
        maruchi_coop_enemy_defeated
      end
    end
  end

  #----------------------------------------------------------------------------
  # Hook Game_Player:
  # - Intercept map transfers -> send REQ_TRANSFER to server for party-wide sync
  # - Forward map event interactions to server
  # - Suppress local contact/projectile self-damage & Scene_Gameover
  # - Lock movement & commands while downed awaiting revive
  # - Forward top-level XAS weapon shots to server & suppress duplicate tokens
  #----------------------------------------------------------------------------
  class Game_Player
    alias maruchi_coop_reserve_transfer reserve_transfer
    def reserve_transfer(map_id, x, y, direction = 2)
      if Maruchi::Coop.connected? && !Maruchi::Coop.applying_server_map?
        Maruchi::Coop.request_transfer(map_id, x, y, direction)
        return
      end
      maruchi_coop_reserve_transfer(map_id, x, y, direction)
    end

    alias maruchi_coop_movable? movable?
    def movable?
      return false if Maruchi::Coop.connected? && (Maruchi::Coop.my_downed? || Maruchi::Coop.cutscene_locked?)
      maruchi_coop_movable?
    end

    if method_defined?(:check_action_event)
      alias maruchi_coop_check_action_event check_action_event
      def check_action_event
        if Maruchi::Coop.connected?
          return false if Maruchi::Coop.my_downed? || Maruchi::Coop.cutscene_locked?
          Maruchi::Coop.request_interact
          return true
        end
        maruchi_coop_check_action_event
      end
    end

    if method_defined?(:can_use_command?)
      alias maruchi_coop_can_use_command? can_use_command?
      def can_use_command?
        return false if Maruchi::Coop.connected? && (Maruchi::Coop.my_downed? || Maruchi::Coop.cutscene_locked?)
        maruchi_coop_can_use_command?
      end
    end

    if method_defined?(:attack_effect)
      alias maruchi_coop_player_attack_effect attack_effect
      def attack_effect(attacker)
        return false if Maruchi::Coop.connected?
        maruchi_coop_player_attack_effect(attacker)
      end
    end

    if method_defined?(:action_effect)
      alias maruchi_coop_player_action_effect action_effect
      def action_effect(bullet, action_id)
        return false if Maruchi::Coop.connected?
        maruchi_coop_player_action_effect(bullet, action_id)
      end
    end

    if method_defined?(:execute_actor_defeated_process)
      alias maruchi_coop_actor_defeated execute_actor_defeated_process
      def execute_actor_defeated_process
        return if Maruchi::Coop.connected?
        maruchi_coop_actor_defeated
      end
    end

    if method_defined?(:shoot)
      alias maruchi_coop_shoot shoot
      def shoot(action_id)
        if Maruchi::Coop.connected? && action_id.to_i > 0
          return if Maruchi::Coop.my_downed? || Maruchi::Coop.cutscene_locked?
          @maruchi_top_shoot = (@force_action_times.to_i == 0)
        else
          @maruchi_top_shoot = false
        end
        begin
          maruchi_coop_shoot(action_id)
        ensure
          @maruchi_top_shoot = false
        end
      end
    end

    if method_defined?(:tools_on_map?)
      alias maruchi_coop_tools_on_map? tools_on_map?
      def tools_on_map?(skill_id)
        return false if Maruchi::Coop.connected?
        maruchi_coop_tools_on_map?(skill_id)
      end
    end

    if method_defined?(:execute_call_event)
      alias maruchi_coop_execute_call_event execute_call_event
      def execute_call_event(action_id)
        if Maruchi::Coop.connected?
          if @maruchi_top_shoot && action_id.to_i > 0
            @maruchi_top_shoot = false
            Maruchi::Coop.send_action("SHOOT", action_id.to_i, @direction, Input.dir8)
          end
          return nil
        end
        maruchi_coop_execute_call_event(action_id)
      end
    end

    if method_defined?(:fake_shoot)
      alias maruchi_coop_fake_shoot fake_shoot
      def fake_shoot(action_id, pos, waittime = 1)
        return nil if Maruchi::Coop.connected?
        maruchi_coop_fake_shoot(action_id, pos, waittime)
      end
    end

    if method_defined?(:check_treasure_here)
      alias maruchi_coop_check_treasure_here check_treasure_here
      def check_treasure_here
        return if Maruchi::Coop.connected?
        maruchi_coop_check_treasure_here
      end
    end
  end
end
