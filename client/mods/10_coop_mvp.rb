#==============================================================================
# Maruchi Co-op Client (Step 4.1: Projectiles, Actions, FX, Enemy Death & Drops)
# Strictly Ruby 1.8.1 / RGSS2 compatible
# - Press F7 on Title or Map to connect/join the headless server (or AUTO_JOIN=1)
# - Renders remote players with smooth interpolation, action poses & name tags
# - Renders server-authoritative projectiles (Token_Bullet) & item drops (treasure)
# - Syncs authoritative combat animations, damage popups, SEs, enemy collapse & drops
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
    attr_accessor :player_id, :player_name, :actor_id, :team, :hp, :maxhp
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

    def apply_snapshot(p)
      @player_name = p[:name] if p[:name] && !p[:name].empty?
      @actor_id    = p[:actor_id]
      @team        = p[:team]
      @hp          = p[:hp]
      @maxhp       = p[:maxhp]
      @battler.hp    = @hp
      @battler.maxhp = @maxhp
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
      # Smoothly interpolate toward latest authoritative real_x/real_y
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

      # Sync action pose frame directly when step_anime (weapon swing / cast) is active
      if @remote_step_anime
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
  # Rendered natively by Sprite_Character on Spriteset_Map
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
      @remote_tokens  = {}
      @enemy_targets  = {}
      @seq = 0
      @send_tick = 0
      @ping_tick = 0
      @rtt_ms = nil
      @last_state = Maruchi::Net::STATE_DISCONNECTED
      @status_note = "F7: Join Coop"

      def self.active?;         @active;         end
      def self.connected?;      @welcomed && Maruchi::Net.connected?; end
      def self.my_id;           @my_id;          end
      def self.remote_players;  @remote_players; end
      def self.remote_tokens;   @remote_tokens;  end

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
        @remote_tokens.clear
        @enemy_targets.clear
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
        @remote_tokens.clear
        @enemy_targets.clear
        @status_note = "Offline (F7)"
      end

      def self.ensure_map_scene_for_join(map_id, sx, sy)
        # Ensure we have a valid party actor (Map #161 intro starts with empty party)
        if $game_party && $game_party.members.empty?
          aid = Maruchi::Config::ACTOR_ID
          aid = 1 unless $data_actors && $data_actors[aid]
          $game_party.add_actor(aid)
        end

        @remote_tokens.clear
        @enemy_targets.clear

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

      def self.send_action(kind, action_id, dir, dir8 = 0)
        return unless connected?
        Maruchi::Net.send_msg(Maruchi::Protocol.build_action(kind, action_id, dir, dir8))
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
        Maruchi::Net.poll_all(128).each do |payload|
          handle_message(payload)
        end

        # Smooth interpolation for remote players, tokens, and enemies
        @remote_players.each_value { |rp| rp.update }
        @remote_tokens.each_value  { |tk| tk.update }
        update_enemy_interpolation if connected? && $scene.is_a?(Scene_Map) && $game_map

        # Send local player state at 30Hz (every 2 frames) while on Scene_Map
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
          @server_map_id = mid
          ensure_map_scene_for_join(mid, sx, sy)

        when "SNAP"
          return unless @welcomed && @my_id
          # SNAP server_tick map_id players_blob enemies_blob [tokens_blob]
          snap_map = f[2].to_i
          players  = Maruchi::Protocol.parse_snapshot_players(f[3])
          enemies  = Maruchi::Protocol.parse_snapshot_enemies(f[4])
          tokens   = (f.length > 5) ? Maruchi::Protocol.parse_snapshot_tokens(f[5]) : []

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

        when "JOIN", "LEAVE"
          Maruchi::Log.info("Server EVENT: #{kind} #{f[2..-1].inspect}")
        end
      end

      def self.handle_enemy_dead(ev_id, enemy_id, exp, gold)
        Sound.play_enemy_collapse rescue nil

        # Trigger local collapse visual + EXP/Gold popup on the enemy sprite
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

        # Grant authoritative EXP, Gold, and kill counters to local party
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

          # Record interpolation target (snap if first time or large teleport)
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
  # Hook Sprite_Character: Protect enemy HP meter plugin (180) from RemotePlayer
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
  # Hook Game_Event: Suppress local autonomous movement, hit math & defeat math
  # when connected to authoritative server
  #----------------------------------------------------------------------------
  class Game_Event
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
  # - Forward top-level XAS weapon shots (shoot) to authoritative server
  # - Suppress duplicate local Token_Bullet spawns (server streams all tokens)
  # - Delegate treasure pickup to authoritative server
  #----------------------------------------------------------------------------
  class Game_Player
    if method_defined?(:shoot)
      alias maruchi_coop_shoot shoot
      def shoot(action_id)
        if Maruchi::Coop.connected? && action_id.to_i > 0
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
