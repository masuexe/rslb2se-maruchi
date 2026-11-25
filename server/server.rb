# frozen_string_literal: false

#==============================================================================
# Maruchi Cross-Platform Authoritative Headless Server (Linux & Windows)
# Usage:
#   ruby server/server.rb [--host 0.0.0.0] [--port 27890] [--map 116] [--game-dir ./game]
#==============================================================================

require "optparse"
require "socket"
require_relative "rgss2/runtime"
require_relative "../shared/protocol"

module Maruchi
  class ClientSession
    MAX_FRAME_LEN = 1024 * 1024

    attr_reader :id, :socket, :peer
    attr_accessor :name, :actor_id, :team, :authed
    attr_accessor :x, :y, :real_x, :real_y, :dir, :dir8, :moving
    attr_accessor :char_name, :char_index, :pattern, :step_anime
    attr_accessor :hp, :maxhp, :mp, :maxmp
    attr_accessor :actor, :player_obj, :last_seen_at, :closed

    def initialize(id, socket, spawn_x, spawn_y, default_actor_id = 1)
      @id = id
      @socket = socket
      @peer = begin
        addr = socket.peeraddr
        "#{addr[3]}:#{addr[1]}"
      rescue StandardError
        "unknown"
      end
      @name = "Player#{id}"
      @actor_id = default_actor_id
      @team = 0
      @authed = false
      @closed = false
      @read_buf = "".b
      @write_buf = "".b
      @last_seen_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @x = spawn_x
      @y = spawn_y
      @real_x = spawn_x * 256
      @real_y = spawn_y * 256
      @dir = 2
      @dir8 = 0
      @moving = false
      @pattern = 1
      @step_anime = false

      @player_obj = Game_Player.new
      @player_obj.moveto(@x, @y)
      @player_obj.refresh
      @player_obj.instance_variable_set(:@maruchi_session_id, @id)

      # Give each player their own authoritative battler reference
      @player_obj.define_singleton_method(:battler) do
        @maruchi_actor || ($game_party && $game_party.members[0])
      end
      @player_obj.define_singleton_method(:maruchi_session_id) do
        @maruchi_session_id
      end

      set_actor!(default_actor_id)
    end

    def set_actor!(aid)
      aid = 1 unless aid.to_i > 0 && $data_actors && $data_actors[aid.to_i]
      @actor_id = aid.to_i
      @actor = Game_Actor.new(@actor_id)
      @player_obj.instance_variable_set(:@maruchi_actor, @actor)
      data_actor = $data_actors[@actor_id]
      @char_name  = data_actor ? data_actor.character_name.to_s : ""
      @char_index = data_actor ? data_actor.character_index.to_i : 0
      @hp    = @actor.hp
      @maxhp = @actor.maxhp
      @mp    = @actor.mp
      @maxmp = @actor.maxmp
      sync_player_obj!
    end

    def sync_player_obj!
      @player_obj.instance_variable_set(:@x, @x)
      @player_obj.instance_variable_set(:@y, @y)
      @player_obj.instance_variable_set(:@real_x, @real_x)
      @player_obj.instance_variable_set(:@real_y, @real_y)
      @player_obj.instance_variable_set(:@direction, @dir)
      @player_obj.instance_variable_set(:@character_name, @char_name) unless @char_name.empty?
      @player_obj.instance_variable_set(:@character_index, @char_index)
      @player_obj.instance_variable_set(:@pattern, @pattern)
      @player_obj.instance_variable_set(:@step_anime, @step_anime)
      if @player_obj.respond_to?(:diagonal_direction=)
        diag = [1, 3, 7, 9].include?(@dir8) ? @dir8 : 0
        @player_obj.diagonal_direction = diag
      end
      if @actor
        @hp    = @actor.hp
        @maxhp = @actor.maxhp
        @mp    = @actor.mp
        @maxmp = @actor.maxmp
      end
    end

    def queue_frame(payload_utf8)
      return if @closed
      bytes = payload_utf8.to_s.b
      return if bytes.bytesize > MAX_FRAME_LEN
      @write_buf << [bytes.bytesize].pack("N")
      @write_buf << bytes
    end

    def flush_writes
      return if @closed || @write_buf.empty?
      written = @socket.write_nonblock(@write_buf, exception: false)
      case written
      when :wait_writable
        # Keep buffered for next tick
      when nil, 0
        close!
      else
        @write_buf.slice!(0, written)
      end
    rescue StandardError
      close!
    end

    def read_frames
      frames = []
      return frames if @closed

      loop do
        chunk = @socket.read_nonblock(4096, exception: false)
        case chunk
        when :wait_readable
          break
        when nil
          close!
          break
        else
          @read_buf << chunk
          @last_seen_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      while @read_buf.bytesize >= 4
        len = @read_buf.byteslice(0, 4).unpack1("N")
        if len > MAX_FRAME_LEN
          close!
          break
        end
        break if @read_buf.bytesize < 4 + len
        raw = @read_buf.byteslice(4, len)
        @read_buf.slice!(0, 4 + len)
        frames << raw.force_encoding(Encoding::UTF_8)
      end

      frames
    rescue StandardError
      close!
      frames
    end

    def to_snapshot_hash
      {
        :id         => @id,
        :name       => @name,
        :actor_id   => @actor_id,
        :team       => @team,
        :x          => @x,
        :y          => @y,
        :real_x     => @real_x,
        :real_y     => @real_y,
        :dir        => @dir,
        :char_name  => @char_name,
        :char_index => @char_index,
        :hp         => @hp,
        :maxhp      => @maxhp,
        :moving     => @moving,
        :pattern    => @pattern,
        :step_anime => @step_anime
      }
    end

    def close!
      return if @closed
      @closed = true
      @socket.close rescue nil
    end
  end

  class HeadlessServer
    attr_reader :sessions, :map_id, :spawn_x, :spawn_y, :tick

    def initialize(options)
      @host      = options[:host]
      @port      = options[:port]
      @game_dir  = options[:game_dir]
      @map_id    = options[:map_id]
      @mode      = options[:mode]
      @tick_rate = options[:tick_rate]
      @snap_rate = options[:snap_rate]
      @snap_interval = [(@tick_rate.to_f / @snap_rate).round, 1].max

      @sessions = {}
      @next_player_id = 1
      @tick = 0
      @running = false
      @pending_se = []
      @capture_se = false
      @pending_dead_enemies = []
    end

    def boot_world!
      log("Booting headless RGSS2 runtime on #{RUBY_PLATFORM} (Ruby #{RUBY_VERSION})...")
      rt = Maruchi::HeadlessRuntime.boot!(game_dir: @game_dir, verbose: true)
      raise "Failed to load #{rt.failed_scripts.size} game scripts" unless rt.failed_scripts.empty?
      log("Loaded #{rt.loaded_scripts.size} game scripts (0 failed).")

      $data_actors        = load_data("Data/Actors.rvdata")
      $data_classes       = load_data("Data/Classes.rvdata")
      $data_skills        = load_data("Data/Skills.rvdata")
      $data_items         = load_data("Data/Items.rvdata")
      $data_weapons       = load_data("Data/Weapons.rvdata")
      $data_armors        = load_data("Data/Armors.rvdata")
      $data_enemies       = load_data("Data/Enemies.rvdata")
      $data_troops        = load_data("Data/Troops.rvdata")
      $data_states        = load_data("Data/States.rvdata")
      $data_animations    = load_data("Data/Animations.rvdata")
      $data_common_events = load_data("Data/CommonEvents.rvdata")
      $data_system        = load_data("Data/System.rvdata")
      $data_areas         = load_data("Data/Areas.rvdata")
      $data_mapinfos      = load_data("Data/MapInfos.rvdata")

      $game_temp          = Game_Temp.new
      $game_message       = Game_Message.new
      $game_system        = Game_System.new
      $game_switches      = Game_Switches.new
      $game_variables     = Game_Variables.new
      $game_self_switches = Game_SelfSwitches.new
      $game_actors        = Game_Actors.new
      $game_party         = Game_Party.new
      $game_troop         = Game_Troop.new
      $game_map           = Game_Map.new
      $game_player        = Game_Player.new
      if defined?(Scene_Title) && Scene_Title.instance_methods.include?(:create_game_objects)
        Scene_Title.allocate.send(:create_game_objects)
      end

      $game_party.add_actor(1)
      $game_map.setup(@map_id)
      @spawn_x, @spawn_y = find_safe_spawn($game_map)
      $game_player.moveto(@spawn_x, @spawn_y)
      $game_player.refresh

      install_multiplayer_hooks!

      enemy_cnt = active_enemy_events.size
      log("World ready: Map ##{@map_id} (#{$game_map.width}x#{$game_map.height}), spawn=(#{@spawn_x},#{@spawn_y}), enemies=#{enemy_cnt}, mode=#{@mode}")
    end

    def start!
      boot_world!
      @tcp = TCPServer.new(@host, @port)
      @tcp.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1) rescue nil
      @running = true
      log("Listening on #{@host}:#{@port} (tick=#{@tick_rate}Hz, snapshot=#{@snap_rate}Hz)")

      trap("INT")  { @running = false }
      trap("TERM") { @running = false } rescue nil

      tick_dt = 1.0 / @tick_rate
      next_tick_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      while @running
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now < next_tick_at
          sleep_time = next_tick_at - now
          sleep(sleep_time) if sleep_time > 0.001
          next
        end

        step_tick!
        next_tick_at += tick_dt
        # Catch up without spiral of death if system paused
        if now - next_tick_at > 0.25
          next_tick_at = now + tick_dt
        end
      end
    ensure
      shutdown!
    end

    def step_tick!
      @pending_se.clear
      @pending_dead_enemies.clear

      accept_new_clients
      @capture_se = true
      process_client_frames

      @tick += 1
      Graphics.update

      # Only advance world simulation when at least one player is connected (saves CPU when idle)
      if !@sessions.empty?
        authed_sessions = @sessions.values.select { |s| s.authed && !s.closed }
        unless authed_sessions.empty?
          # Drive per-player XAS action/multi-shoot timers and treasure pickups
          authed_sessions.each do |session|
            with_session_context(session) do
              po = session.player_obj
              po.action_update if po.respond_to?(:action_update)
              if po.respond_to?(:can_force_action?) && po.can_force_action?
                po.update_force_action
              end
              check_session_treasure_pickup!(session)
            end
          end

          # Bind $game_player to first active player during map tick; enemy AI hook overrides per-enemy
          first_session = authed_sessions.first
          with_session_context(first_session) do
            begin
              $game_system.update
              $game_map.update
              update_server_enemy_collapses!
            rescue StandardError => e
              log("WARN tick ##{@tick} world update error: #{e.class}: #{e.message}")
            end
          end

          collect_and_broadcast_fx!(authed_sessions)

          if (@tick % @snap_interval) == 0
            broadcast_snapshot!
          end
        end
      end

      @capture_se = false
      flush_and_cleanup_clients
    end

    def record_se(filename, volume, pitch)
      return unless @capture_se
      return if filename.nil? || filename.empty?
      return if @pending_se.size >= 4
      key = filename.to_s
      return if @pending_se.any? { |s| s[0] == key }
      @pending_se << [key, volume.to_i, pitch.to_i]
    end

    def record_enemy_defeated(ev, enemy)
      return unless ev && enemy
      exp  = ev.battler ? ev.battler.exp.to_i : enemy.exp.to_i
      gold = ev.battler ? ev.battler.gold.to_i : enemy.gold.to_i
      @pending_dead_enemies << [ev.id, enemy.id, exp, gold]
      log("Enemy defeated: ev##{ev.id} (enemy_id=#{enemy.id}, exp=#{exp}, gold=#{gold})")
    end

    def with_session_context(session)
      prev_player = $game_player
      session.sync_player_obj!
      $game_player = session.player_obj
      yield
    ensure
      $game_player = prev_player
    end

    def nearest_session_to(ex, ey)
      best = nil
      best_d = 999_999
      @sessions.each_value do |s|
        next if s.closed || !s.authed
        d = (s.x - ex).abs + (s.y - ey).abs
        if d < best_d
          best_d = d
          best = s
        end
      end
      best
    end

    private

    def install_multiplayer_hooks!
      server = self
      $MARUCHI_SERVER = server

      # Ensure Game_Map#id exists (XAS make_treasure calls $game_map.id)
      unless Game_Map.method_defined?(:id)
        Game_Map.class_eval do
          alias_method :id, :map_id
        end
      end

      # Hook Audio.se_play to capture authoritative combat/action SEs for broadcast
      unless Audio.respond_to?(:maruchi_orig_se_play)
        Audio.singleton_class.class_eval do
          alias_method :maruchi_orig_se_play, :se_play
          def se_play(filename, volume = 100, pitch = 100)
            srv = $MARUCHI_SERVER
            srv.record_se(filename, volume, pitch) if srv
            maruchi_orig_se_play(filename, volume, pitch)
          end
        end
      end

      # Hook Game_Event#update for multi-player enemy aggro & owner-bound projectile context
      Game_Event.class_eval do
        unless method_defined?(:maruchi_orig_update)
          alias_method :maruchi_orig_update, :update
          def update
            srv = $MARUCHI_SERVER
            if srv && !srv.sessions.empty?
              if respond_to?(:battler) && battler.is_a?(Game_Enemy)
                target = srv.nearest_session_to(x, y)
                if target
                  srv.with_session_context(target) { maruchi_orig_update }
                  return
                end
              elsif is_a?(Token_Bullet) && @action && @action.user.is_a?(Game_Player)
                prev = $game_player
                $game_player = @action.user
                begin
                  maruchi_orig_update
                ensure
                  $game_player = prev
                end
                return
              end
            end
            maruchi_orig_update
          end
        end
      end

      # Hook Game_Character#execute_enemy_defeated_process to broadcast authoritative death & rewards
      Game_Character.class_eval do
        if method_defined?(:execute_enemy_defeated_process) && !method_defined?(:maruchi_orig_enemy_defeated)
          alias_method :maruchi_orig_enemy_defeated, :execute_enemy_defeated_process
          def execute_enemy_defeated_process
            enemy = (self.battler && $data_enemies) ? $data_enemies[self.battler.enemy_id] : nil
            maruchi_orig_enemy_defeated
            srv = $MARUCHI_SERVER
            if srv && is_a?(Game_Event) && enemy
              srv.record_enemy_defeated(self, enemy)
            end
          end
        end
      end

      # Ensure make_treasure works reliably on headless server (guard page.list & $game_map.id)
      if defined?(XAS_BA_ItemDrop) && XAS_BA_ItemDrop.method_defined?(:make_treasure)
        XAS_BA_ItemDrop.module_eval do
          unless method_defined?(:maruchi_orig_make_treasure)
            alias_method :maruchi_orig_make_treasure, :make_treasure
            def make_treasure(enemy)
              maruchi_orig_make_treasure(enemy)
            rescue StandardError => e
              srv = $MARUCHI_SERVER
              srv.send(:log, "WARN make_treasure error: #{e.class}: #{e.message}") if srv
            end
          end
        end
      end
    end

    # Headless server has no Sprite_Character, so drive enemy collapse countdown & erase here
    def update_server_enemy_collapses!
      $game_map.events.values.each do |ev|
        next if ev.erased
        next unless ev.respond_to?(:battler) && ev.battler.is_a?(Game_Enemy)
        cd = ev.respond_to?(:collapse_duration) ? ev.collapse_duration.to_i : 0
        next unless cd > 0
        ev.collapse_duration = cd - 2
        cur_op = ev.opacity.to_i
        ev.opacity = [cur_op - 4, 0].max
        if ev.collapse_duration <= 0
          ev.opacity = 0
          ev.erase
        end
      end
    end

    # Authoritative treasure pickup check for every connected player
    def check_session_treasure_pickup!(session)
      $game_map.events_xy(session.x, session.y).each do |ev|
        next if ev.erased
        next unless ev.respond_to?(:treasure) && ev.treasure != nil
        tr_kind = ev.treasure[0].to_i
        tr_id   = ev.treasure[1].to_i
        item = case tr_kind
               when 1 then $data_items[tr_id]
               when 2 then $data_weapons[tr_id]
               when 3 then $data_armors[tr_id]
               else nil
               end
        ev.erase
        if item && tr_kind == 1 && session.actor
          apply_server_field_item!(session, item)
        end
        log("Player ##{session.id} picked up treasure kind=#{tr_kind} id=#{tr_id} (#{item ? item.name : '?'})")
        broadcast_frame(Maruchi::Protocol.build_event("PICKUP", session.id, tr_kind, tr_id))
      end
    end

    def apply_server_field_item!(session, item)
      note = item.note.to_s
      if note =~ /<Drop HP Damage = (\S+)>/
        dmg = ($1.to_i * session.actor.maxhp) / 100
        session.actor.hp -= dmg
      elsif note =~ /<Drop MP Damage = (\S+)>/
        dmg = ($1.to_i * session.actor.maxmp) / 100
        session.actor.mp -= dmg
      elsif note =~ /<Drop Gold = (\d+)>/
        $game_party.gain_gold($1.to_i)
      end
    end

    # Capture & broadcast all authoritative animations, damage pops, deaths, and SEs generated this tick
    def collect_and_broadcast_fx!(authed_sessions)
      # 1. Enemy deaths
      @pending_dead_enemies.each do |ev_id, enemy_id, exp, gold|
        broadcast_frame(Maruchi::Protocol.build_event("ENEMY_DEAD", ev_id, enemy_id, exp, gold))
      end

      # 2. Player animations & damage pops
      authed_sessions.each do |s|
        po = s.player_obj
        if po.animation_id.to_i > 0
          aid = po.animation_id.to_i
          po.animation_id = 0
          broadcast_frame(Maruchi::Protocol.build_event("FX_ANI", "P", s.id, aid))
        end
        b = s.actor
        if b && b.damage_pop
          dmg_str  = b.damage.to_s
          dmg_type = b.damage_type.to_s
          crit     = b.critical ? 1 : 0
          b.damage      = nil
          b.damage_type = ""
          b.critical    = false
          b.damage_pop  = false
          broadcast_frame(Maruchi::Protocol.build_event("FX_DMG", "P", s.id, dmg_str, dmg_type, crit))
        end
      end

      # 3. Map event (enemy + token) animations & damage pops
      $game_map.events.each_value do |ev|
        t_type = ev.is_a?(Token_Event) ? "T" : "E"
        if ev.animation_id.to_i > 0
          aid = ev.animation_id.to_i
          ev.animation_id = 0
          broadcast_frame(Maruchi::Protocol.build_event("FX_ANI", t_type, ev.id, aid))
        end
        if ev.respond_to?(:battler) && ev.battler && ev.battler.damage_pop
          b = ev.battler
          dmg_str  = b.damage.to_s
          dmg_type = b.damage_type.to_s
          crit     = b.critical ? 1 : 0
          b.damage      = nil
          b.damage_type = ""
          b.critical    = false
          b.damage_pop  = false
          broadcast_frame(Maruchi::Protocol.build_event("FX_DMG", t_type, ev.id, dmg_str, dmg_type, crit))
        end
      end

      # 4. Combat/action SEs
      @pending_se.each do |se_name, vol, pitch|
        broadcast_frame(Maruchi::Protocol.build_event("FX_SE", se_name, vol, pitch))
      end
    end

    def find_safe_spawn(map)
      cx = map.width / 2
      cy = map.height / 2
      (0..[map.width, map.height].max).each do |r|
        ((cy - r)..(cy + r)).each do |y|
          next if y < 1 || y >= map.height - 1
          ((cx - r)..(cx + r)).each do |x|
            next if x < 1 || x >= map.width - 1
            return [x, y] if map.passable?(x, y) && map.events_xy(x, y).empty?
          end
        end
      end
      [1, 1]
    end

    def active_enemy_events
      list = []
      $game_map.events.each_value do |ev|
        next unless ev.respond_to?(:battler) && ev.battler.is_a?(Game_Enemy)
        list << ev
      end
      list
    end

    def active_token_events
      list = []
      $game_map.events.each_value do |ev|
        next unless ev.is_a?(Token_Event)
        next if ev.erased
        list << ev
      end
      list
    end

    def accept_new_clients
      loop do
        sock = @tcp.accept_nonblock(exception: false)
        break if sock == :wait_readable || sock.nil?
        sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) rescue nil
        pid = @next_player_id
        @next_player_id += 1
        session = ClientSession.new(pid, sock, @spawn_x, @spawn_y)
        session.team = (@mode == "pvp") ? pid : 0
        @sessions[pid] = session
        log("Client ##{pid} connected from #{session.peer} (online=#{@sessions.size})")
      end
    rescue StandardError => e
      log("WARN accept error: #{e.class}: #{e.message}")
    end

    def process_client_frames
      @sessions.each_value do |session|
        next if session.closed
        session.read_frames.each do |payload|
          handle_message(session, payload)
        end
      end
    end

    def handle_message(session, payload)
      fields = Maruchi::Protocol.unpack(payload)
      return if fields.empty?

      case fields[0]
      when "HELLO"
        _ver = fields[1].to_i
        name = Maruchi::Protocol.unesc(fields[2])
        actor_id = fields[3].to_i
        session.name = name unless name.empty?
        session.set_actor!(actor_id)
        session.authed = true
        log("Client ##{session.id} HELLO name='#{session.name}' actor=#{session.actor_id} (#{session.actor ? session.actor.name : '?'})")
        session.queue_frame(
          Maruchi::Protocol.build_welcome(session.id, @map_id, @spawn_x, @spawn_y, @mode, @tick_rate)
        )
        broadcast_frame(
          Maruchi::Protocol.build_event("JOIN", session.id, session.name),
          exclude_id: session.id
        )
        # Immediately send an initial snapshot so the new client sees everyone right away
        send_snapshot_to(session)

      when "PSTATE"
        # PSTATE seq x y real_x real_y dir moving char_name char_index actor_id dir8 btn_mask [pattern step_anime]
        return if fields.length < 13
        nx = fields[2].to_i
        ny = fields[3].to_i
        nrx = fields[4].to_i
        nry = fields[5].to_i
        ndir = fields[6].to_i
        nmov = (fields[7].to_i != 0)
        cname = Maruchi::Protocol.unesc(fields[8])
        cidx  = fields[9].to_i
        aid   = fields[10].to_i
        ndir8 = fields[11].to_i

        # Basic bounds validation against authoritative map dimensions
        if nx >= 0 && nx < $game_map.width && ny >= 0 && ny < $game_map.height
          session.x = nx
          session.y = ny
          session.real_x = nrx
          session.real_y = nry
        end
        session.dir = ndir if [2, 4, 6, 8].include?(ndir)
        session.dir8 = ndir8
        session.moving = nmov
        session.char_name = cname unless cname.empty?
        session.char_index = cidx
        if aid > 0 && aid != session.actor_id && $data_actors[aid]
          session.set_actor!(aid)
          session.char_name = cname unless cname.empty?
          session.char_index = cidx
        end
        if fields.length > 13
          session.pattern = fields[13].to_i
        end
        if fields.length > 14
          session.step_anime = (fields[14].to_i != 0)
        end
        session.sync_player_obj!

      when "ACTION"
        kind = Maruchi::Protocol.unesc(fields[1])
        action_id = fields[2].to_i
        return if action_id <= 0
        dir  = fields[3].to_i
        dir8 = fields.length > 4 ? fields[4].to_i : 0
        session.dir = dir if [2, 4, 6, 8].include?(dir)
        session.dir8 = dir8
        if kind == "SHOOT" && action_id > 0 && session.player_obj.respond_to?(:shoot)
          with_session_context(session) do
            begin
              # Step 4.1: Keep MP topped up on server until Step 4.2 introduces full authoritative MP sync
              if session.actor && $data_skills[action_id]
                need_mp = $data_skills[action_id].mp_cost.to_i + 2
                session.actor.mp = need_mp if session.actor.mp < need_mp
              end
              $game_player.shoot(action_id)
            rescue StandardError => e
              log("WARN shoot error for player ##{session.id} (action=#{action_id}): #{e.class}: #{e.message}")
            end
          end
        end
        broadcast_frame(
          Maruchi::Protocol.build_event("ACTION", session.id, kind, action_id, session.dir),
          exclude_id: session.id
        )

      when "PING"
        client_ms = fields[1].to_i
        session.queue_frame(Maruchi::Protocol.build_pong(client_ms, @tick))
      end
    end

    def build_current_snapshot_frame
      players = @sessions.values.select { |s| s.authed && !s.closed }.map(&:to_snapshot_hash)
      enemies = active_enemy_events.map do |ev|
        b = ev.battler
        {
          :id           => ev.id,
          :x            => ev.x,
          :y            => ev.y,
          :real_x       => ev.real_x,
          :real_y       => ev.real_y,
          :dir          => ev.direction,
          :hp           => b ? b.hp : 0,
          :maxhp        => b ? b.maxhp : 0,
          :erased       => !!ev.instance_variable_get(:@erased),
          :opacity      => ev.opacity.to_i,
          :collapse_dur => ev.respond_to?(:collapse_duration) ? ev.collapse_duration.to_i : 0,
          :defeated     => (b && b.respond_to?(:defeated)) ? !!b.defeated : false
        }
      end
      tokens = active_token_events.map do |tk|
        is_treasure = (tk.respond_to?(:treasure) && tk.treasure != nil)
        jmp_y = tk.respond_to?(:jump_height, true) ? tk.send(:jump_height).to_i : 0
        icon_val = tk.respond_to?(:icon_name) ? tk.icon_name : nil
        {
          :id         => tk.id,
          :kind       => is_treasure ? 1 : 0,
          :x          => tk.x,
          :y          => tk.y,
          :real_x     => tk.real_x,
          :real_y     => tk.real_y,
          :dir        => tk.direction,
          :char_name  => tk.character_name.to_s,
          :char_index => tk.character_index.to_i,
          :pattern    => tk.pattern.to_i,
          :opacity    => tk.opacity.to_i,
          :blend_type => tk.blend_type.to_i,
          :angle      => (tk.respond_to?(:angle) ? tk.angle.to_f.round : 0),
          :zoom_x     => (tk.respond_to?(:zoom_x) ? (tk.zoom_x.to_f * 100.0).round : 100),
          :zoom_y     => (tk.respond_to?(:zoom_y) ? (tk.zoom_y.to_f * 100.0).round : 100),
          :icon_name  => icon_val.nil? ? nil : icon_val.to_i,
          :jump_y     => jmp_y
        }
      end
      Maruchi::Protocol.build_snapshot(@tick, @map_id, players, enemies, tokens)
    end

    def send_snapshot_to(session)
      session.queue_frame(build_current_snapshot_frame)
    end

    def broadcast_snapshot!
      frame = build_current_snapshot_frame
      @sessions.each_value { |s| s.queue_frame(frame) if s.authed && !s.closed }
    end

    def broadcast_frame(frame, exclude_id: nil)
      @sessions.each_value do |s|
        next if s.closed || !s.authed || s.id == exclude_id
        s.queue_frame(frame)
      end
    end

    def flush_and_cleanup_clients
      disconnected = []
      @sessions.each do |pid, s|
        s.flush_writes unless s.closed
        disconnected << pid if s.closed
      end
      disconnected.each do |pid|
        s = @sessions.delete(pid)
        log("Client ##{pid} ('#{s.name}') disconnected (online=#{@sessions.size})")
        broadcast_frame(Maruchi::Protocol.build_event("LEAVE", pid, s.name))
      end
    end

    def shutdown!
      log("Shutting down server...")
      @sessions.each_value(&:close!)
      @sessions.clear
      @tcp.close if @tcp && !@tcp.closed?
    end

    def log(msg)
      ts = Time.now.strftime("%H:%M:%S")
      puts("[#{ts}][SERVER] #{msg}")
      $stdout.flush
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  repo_root = File.expand_path("..", __dir__)
  options = {
    :host      => "0.0.0.0",
    :port      => 27890,
    :game_dir  => File.join(repo_root, "game"),
    :map_id    => 116,
    :mode      => "coop",
    :tick_rate => 60,
    :snap_rate => 30
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby server/server.rb [options]"
    opts.on("--host HOST", "Bind host (default: 0.0.0.0)") { |v| options[:host] = v }
    opts.on("--port PORT", Integer, "TCP port (default: 27890)") { |v| options[:port] = v }
    opts.on("--game-dir DIR", "Path to extracted game directory") { |v| options[:game_dir] = v }
    opts.on("--map ID", Integer, "Starting map ID (default: 116)") { |v| options[:map_id] = v }
    opts.on("--mode MODE", "Room mode: coop or pvp (default: coop)") { |v| options[:mode] = v }
    opts.on("--tick-rate HZ", Integer, "Server tick rate (default: 60)") { |v| options[:tick_rate] = v }
    opts.on("--snap-rate HZ", Integer, "Snapshot broadcast rate (default: 30)") { |v| options[:snap_rate] = v }
  end.parse!

  Maruchi::HeadlessServer.new(options).start!
end
