# frozen_string_literal: false

#==============================================================================
# Maruchi Cross-Platform Authoritative Headless Server (Linux & Windows)
# Step 4.3: Map Transfers, Shared Switches/Variables/Self-Switches,
#           Live Character Selection & Live CO-OP / PVP Mode Switching
# Usage:
#   ruby server/server.rb [--host 0.0.0.0] [--port 27890] [--map 116] [--mode coop|pvp]
#==============================================================================

require "optparse"
require "socket"
require_relative "rgss2/runtime"
require_relative "../shared/protocol"

module Maruchi
  class ClientSession
    MAX_FRAME_LEN = 1024 * 1024
    REVIVE_TICKS  = 300 # 5 seconds at 60Hz (4x faster when an ally stands nearby)

    attr_reader :id, :socket, :peer
    attr_accessor :name, :actor_id, :team, :authed
    attr_accessor :x, :y, :real_x, :real_y, :dir, :dir8, :moving
    attr_accessor :char_name, :char_index, :pattern, :step_anime
    attr_accessor :hp, :maxhp, :mp, :maxmp, :down_timer
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
      @down_timer = 0

      @player_obj = Game_Player.new
      @player_obj.moveto(@x, @y)
      @player_obj.refresh
      @player_obj.instance_variable_set(:@maruchi_session_id, @id)

      @player_obj.define_singleton_method(:battler) do
        @maruchi_actor || ($game_party && $game_party.members[0])
      end
      @player_obj.define_singleton_method(:maruchi_session_id) do
        @maruchi_session_id
      end

      set_actor!(default_actor_id)
    end

    def downed?
      @down_timer > 0
    end

    def alive?
      !@closed && @authed && !downed? && @actor && @actor.hp > 0
    end

    def set_actor!(aid)
      aid = 1 unless aid.to_i > 0 && $data_actors && $data_actors[aid.to_i]
      @actor_id = aid.to_i
      @actor = Game_Actor.new(@actor_id)
      @actor.recover_all
      @actor.invunerable_duration = 120 if @actor.respond_to?(:invunerable_duration=)
      @player_obj.instance_variable_set(:@maruchi_actor, @actor)
      data_actor = $data_actors[@actor_id]
      @char_name  = data_actor ? data_actor.character_name.to_s : ""
      @char_index = data_actor ? data_actor.character_index.to_i : 0
      @down_timer = 0
      refresh_vitals!
      sync_player_obj!
    end

    def refresh_vitals!
      return unless @actor
      @hp    = @actor.hp.to_i
      @maxhp = [@actor.maxhp.to_i, 1].max
      @mp    = @actor.mp.to_i
      @maxmp = @actor.maxmp.to_i
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
      refresh_vitals!
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
      refresh_vitals!
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
        :step_anime => @step_anime,
        :mp         => @mp,
        :maxmp      => @maxmp,
        :down_timer => @down_timer
      }
    end

    def close!
      return if @closed
      @closed = true
      @socket.close rescue nil
    end
  end

  class HeadlessServer
    attr_reader :sessions, :map_id, :spawn_x, :spawn_y, :tick, :mode
    attr_accessor :active_context_session

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
      @pending_knockbacks = []
      @dirty_switches = {}
      @dirty_variables = {}
      @dirty_self_switches = {}
      @pending_transfer = nil
      @active_context_session = nil
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
      @pending_knockbacks.clear

      accept_new_clients
      @capture_se = true
      process_client_frames

      # Apply any queued authoritative map transfer before stepping map simulation
      if @pending_transfer
        mid, tx, ty, tdir = @pending_transfer
        @pending_transfer = nil
        transfer_all_to!(mid, tx, ty, tdir)
      end

      @tick += 1
      Graphics.update

      if !@sessions.empty?
        authed_sessions = @sessions.values.select { |s| s.authed && !s.closed }
        unless authed_sessions.empty?
          authed_sessions.each do |session|
            update_session_tick!(session, authed_sessions)
          end

          first_alive = authed_sessions.find(&:alive?) || authed_sessions.first
          with_session_context(first_alive) do
            begin
              $game_system.update
              $game_map.update
              update_server_enemy_collapses!
            rescue StandardError => e
              log("WARN tick ##{@tick} world update error: #{e.class}: #{e.message}")
            end
          end

          # Apply map transfer if a server event / interpreter triggered reserve_transfer during map tick
          if @pending_transfer
            mid, tx, ty, tdir = @pending_transfer
            @pending_transfer = nil
            transfer_all_to!(mid, tx, ty, tdir)
          end

          authed_sessions.each do |session|
            check_session_downed!(session)
          end

          collect_and_broadcast_fx!(authed_sessions)
          broadcast_dirty_world_state!

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

    def record_player_knockback(session_id, dir, power)
      return if power.to_i <= 0
      @pending_knockbacks << [session_id.to_i, dir.to_i, power.to_i]
    end

    def record_switch_change(switch_id, value)
      return if switch_id.to_i <= 0
      @dirty_switches[switch_id.to_i] = !!value
    end

    def record_variable_change(var_id, value)
      return if var_id.to_i <= 0
      @dirty_variables[var_id.to_i] = value.to_i
    end

    def record_self_switch_change(key, value)
      return unless key.is_a?(Array) && key.length >= 3
      @dirty_self_switches[key] = !!value
    end

    def queue_map_transfer(map_id, x = -1, y = -1, dir = 2)
      return unless valid_map_id?(map_id)
      @pending_transfer = [map_id.to_i, x.to_i, y.to_i, [2, 4, 6, 8].include?(dir.to_i) ? dir.to_i : 2]
    end

    def valid_map_id?(map_id)
      mid = map_id.to_i
      return false if mid <= 0
      return false unless $data_mapinfos && $data_mapinfos[mid]
      path = File.join(@game_dir, "Data", sprintf("Map%03d.rvdata", mid))
      File.file?(path)
    end

    def transfer_all_to!(map_id, req_x = -1, req_y = -1, dir = 2)
      mid = map_id.to_i
      unless valid_map_id?(mid)
        log("WARN invalid map transfer target: Map ##{mid}")
        return false
      end

      $game_map.clear_tokens if $game_map.respond_to?(:clear_tokens)
      $game_map.interpreter.clear if $game_map.interpreter
      $game_map.setup(mid)
      @map_id = mid

      if req_x >= 0 && req_x < $game_map.width && req_y >= 0 && req_y < $game_map.height
        @spawn_x = req_x
        @spawn_y = req_y
      else
        @spawn_x, @spawn_y = find_safe_spawn($game_map)
      end

      @sessions.each_value do |s|
        next if s.closed
        s.x = @spawn_x
        s.y = @spawn_y
        s.real_x = @spawn_x * 256
        s.real_y = @spawn_y * 256
        s.dir = dir if [2, 4, 6, 8].include?(dir)
        s.down_timer = 0
        if s.actor
          s.actor.recover_all if s.actor.hp <= 0
          s.actor.invunerable_duration = 120 if s.actor.respond_to?(:invunerable_duration=)
        end
        s.sync_player_obj!
      end

      map_name = ($data_mapinfos && $data_mapinfos[mid]) ? $data_mapinfos[mid].name : ""
      log("Transferred all players to Map ##{mid} '#{map_name}' at (#{@spawn_x},#{@spawn_y}) enemies=#{active_enemy_events.size}")

      broadcast_frame(Maruchi::Protocol.build_map_transfer(@map_id, @spawn_x, @spawn_y, dir))
      @sessions.each_value do |s|
        next if s.closed || !s.authed
        send_world_state_to(s)
      end
      broadcast_snapshot!
      true
    end

    def switch_mode!(new_mode)
      m = (new_mode.to_s.downcase == "pvp") ? "pvp" : "coop"
      return if m == @mode
      @mode = m
      @sessions.each_value do |s|
        next if s.closed
        s.team = (@mode == "pvp") ? s.id : 0
        s.down_timer = 0
        if s.actor
          s.actor.recover_all
          s.actor.invunerable_duration = 120 if s.actor.respond_to?(:invunerable_duration=)
        end
        s.sync_player_obj!
      end
      log("Room mode switched to #{@mode.upcase}")
      broadcast_frame(Maruchi::Protocol.build_event("MODE_CHANGE", @mode))
      broadcast_snapshot!
    end

    def with_session_context(session)
      prev_player  = $game_player
      prev_session = @active_context_session
      @active_context_session = session
      session.sync_player_obj!
      $game_player = session.player_obj
      yield
    ensure
      $game_player = prev_player
      @active_context_session = prev_session
    end

    def all_active_player_objs
      list = []
      @sessions.each_value do |s|
        next unless s.alive?
        s.sync_player_obj!
        list << s.player_obj
      end
      list
    end

    def session_for_player_obj(po)
      return nil unless po && po.respond_to?(:maruchi_session_id)
      @sessions[po.maruchi_session_id]
    end

    def pvp_hostile?(user_char, target_char)
      return false unless @mode == "pvp"
      return false unless user_char.is_a?(Game_Player) && target_char.is_a?(Game_Player)
      return false if user_char == target_char
      s1 = session_for_player_obj(user_char)
      s2 = session_for_player_obj(target_char)
      return false unless s1 && s2 && s1.alive? && s2.alive?
      s1.team != s2.team
    end

    def nearest_session_to(ex, ey)
      best = nil
      best_d = 999_999
      @sessions.each_value do |s|
        next unless s.alive?
        d = (s.x - ex).abs + (s.y - ey).abs
        if d < best_d
          best_d = d
          best = s
        end
      end
      best
    end

    private

    def update_session_tick!(session, authed_sessions)
      if session.downed?
        speed = 1
        if @mode != "pvp"
          ally_near = authed_sessions.any? do |other|
            other.id != session.id && other.alive? &&
              ((other.x - session.x).abs + (other.y - session.y).abs) <= 2
          end
          speed = 4 if ally_near
        end
        session.down_timer = [session.down_timer - speed, 0].max
        revive_session!(session) if session.down_timer == 0
        return
      end

      with_session_context(session) do
        po = session.player_obj
        b  = session.actor
        if b
          b.invunerable_duration -= 1 if b.respond_to?(:invunerable_duration) && b.invunerable_duration.to_i > 0
          if b.respond_to?(:state_duration) && b.state_duration.is_a?(Hash)
            b.state_duration.keys.each do |sid|
              if b.state_duration[sid].to_i > 0
                b.state_duration[sid] -= 1
                b.remove_state(sid) if b.state_duration[sid] <= 0
              end
            end
          end
        end
        if po.knock_back_duration != nil
          po.knock_back_duration -= 1
          po.knock_back_duration = nil if po.knock_back_duration <= 0
        end

        po.action_update if po.respond_to?(:action_update)
        if po.respond_to?(:can_force_action?) && po.can_force_action?
          po.update_force_action
        end

        check_session_enemy_collision!(session)
        check_session_treasure_pickup!(session)
        check_session_downed!(session)
      end
    end

    def check_session_enemy_collision!(session)
      return unless session.alive?
      return if $game_map.interpreter.running?
      $game_map.events.each_value do |ev|
        next if ev.erased
        next unless ev.respond_to?(:collision_attack) && ev.collision_attack
        next unless ev.respond_to?(:battler) && ev.battler.is_a?(Game_Enemy)
        next if ev.battler.dead?
        if ev.x == session.x && ev.y == session.y
          session.player_obj.attack_effect(ev)
        end
      end
    end

    def check_session_downed!(session)
      return if session.closed || !session.authed || session.downed?
      return unless session.actor && session.actor.hp <= 0
      session.actor.hp = 0
      session.down_timer = ClientSession::REVIVE_TICKS
      session.refresh_vitals!
      log("Player ##{session.id} ('#{session.name}') DOWNED! Revive in #{ClientSession::REVIVE_TICKS / 60}s")
      broadcast_frame(Maruchi::Protocol.build_event("PLAYER_DOWN", session.id, session.down_timer))
    end

    def revive_session!(session)
      return unless session.actor
      session.actor.recover_all
      session.actor.invunerable_duration = 120 if session.actor.respond_to?(:invunerable_duration=)
      session.actor.defeated = false if session.actor.respond_to?(:defeated=)
      session.player_obj.knock_back_duration = nil
      session.down_timer = 0
      if @mode == "pvp" || !$game_map.passable?(session.x, session.y)
        session.x = @spawn_x
        session.y = @spawn_y
        session.real_x = @spawn_x * 256
        session.real_y = @spawn_y * 256
      end
      session.sync_player_obj!
      log("Player ##{session.id} ('#{session.name}') REVIVED at (#{session.x},#{session.y}) hp=#{session.hp}/#{session.maxhp}")
      broadcast_frame(Maruchi::Protocol.build_event("PLAYER_REVIVE", session.id, session.x, session.y))
    end

    def install_multiplayer_hooks!
      server = self
      $MARUCHI_SERVER = server

      unless Game_Map.method_defined?(:id)
        Game_Map.class_eval do
          alias_method :id, :map_id
        end
      end

      # Track shared switches, variables & self-switches mutations for delta broadcast
      Game_Switches.class_eval do
        unless method_defined?(:maruchi_orig_set)
          alias_method :maruchi_orig_set, :[]=
          def []=(switch_id, value)
            prev = self[switch_id]
            res = maruchi_orig_set(switch_id, value)
            if $MARUCHI_SERVER && (!!prev != !!value)
              $MARUCHI_SERVER.record_switch_change(switch_id, value)
            end
            res
          end
        end
      end

      Game_Variables.class_eval do
        unless method_defined?(:maruchi_orig_set)
          alias_method :maruchi_orig_set, :[]=
          def []=(var_id, value)
            prev = self[var_id]
            res = maruchi_orig_set(var_id, value)
            if $MARUCHI_SERVER && (prev.to_i != value.to_i)
              $MARUCHI_SERVER.record_variable_change(var_id, value)
            end
            res
          end
        end
      end

      Game_SelfSwitches.class_eval do
        unless method_defined?(:maruchi_orig_set)
          alias_method :maruchi_orig_set, :[]=
          def []=(key, value)
            prev = self[key]
            res = maruchi_orig_set(key, value)
            if $MARUCHI_SERVER && (!!prev != !!value)
              $MARUCHI_SERVER.record_self_switch_change(key, value)
            end
            res
          end
        end
      end

      # Intercept map transfer commands triggered by server events / doors
      Game_Player.class_eval do
        if method_defined?(:reserve_transfer) && !method_defined?(:maruchi_orig_srv_reserve_transfer)
          alias_method :maruchi_orig_srv_reserve_transfer, :reserve_transfer
          def reserve_transfer(map_id, x, y, direction = 2)
            if $MARUCHI_SERVER
              $MARUCHI_SERVER.queue_map_transfer(map_id, x, y, direction)
              return
            end
            maruchi_orig_srv_reserve_transfer(map_id, x, y, direction)
          end
        end
      end

      Game_Party.class_eval do
        unless method_defined?(:maruchi_orig_members)
          alias_method :maruchi_orig_members, :members
          def members
            srv = $MARUCHI_SERVER
            if srv && srv.active_context_session && srv.active_context_session.actor
              return [srv.active_context_session.actor]
            end
            maruchi_orig_members
          end
        end
      end

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

      if defined?(XAS_ACTION) && XAS_ACTION.method_defined?(:check_event_trigger_attack)
        XAS_ACTION.module_eval do
          unless method_defined?(:maruchi_orig_check_event_trigger_attack)
            alias_method :maruchi_orig_check_event_trigger_attack, :check_event_trigger_attack
            def check_event_trigger_attack
              srv = $MARUCHI_SERVER
              return maruchi_orig_check_event_trigger_attack unless srv && !srv.sessions.empty?
              return unless can_impact_target?

              hit_check = false
              range = @action.attack_range
              hit = []
              targets = srv.all_active_player_objs + $game_map.events.values
              ar = [68,69,70,83,124,125,134,152,153,178,181,204,205,210,211,212,213,214,216,217,218,246,253,277,280,282,299,330,368,396,340,441,461,462,463,469,491,492,493,522,584,594,595,600]
              judge_fix = ((ar.include?(self.tool_id) && self.direction != 8) ? 1 : 0)

              for event in targets
                next if event == self || @action.hit_events.include?(event) || event.erased

                body_size      = event.body_size
                event_center_x = event.x
                event_center_y = event.y - body_size

                if @action.short_range
                  owner = @action.user || $game_player
                  dx = event_center_x - owner.x
                  dy = event_center_y - owner.y
                else
                  dx = event_center_x - self.x
                  dy = event_center_y - self.y + judge_fix
                end
                dx = (dx >= 0 ? [dx - body_size, 0].max : [dx + body_size, 0].min)
                dy = (dy >= 0 ? [dy - body_size, 0].max : [dy + body_size, 0].min)
                hit.push(event) if in_range?(dx, dy, event, range)
              end

              for event in hit
                victim_sess = srv.session_for_player_obj(event)
                if victim_sess
                  srv.with_session_context(victim_sess) do
                    hit_check = true if event.action_effect(self, self.action.attack_id)
                  end
                else
                  hit_check = true if event.action_effect(self, self.action.attack_id)
                  hit_check = true if event.action_effect_page(self, self.action.attack_id)
                end
                @action.hit_events.push(event) unless @action.multi_hit
              end
              $game_temp.active_token = self if hit_check
            end
          end
        end
      end

      if defined?(XRXS_BattlerAttachment) && XRXS_BattlerAttachment.method_defined?(:action_can_hit_target?)
        XRXS_BattlerAttachment.module_eval do
          unless method_defined?(:maruchi_orig_action_can_hit_target?)
            alias_method :maruchi_orig_action_can_hit_target?, :action_can_hit_target?
            def action_can_hit_target?(bullet, user, skill, tar_invu)
              srv = $MARUCHI_SERVER
              if srv && bullet && bullet.action && srv.pvp_hostile?(user, self)
                prev_all = bullet.action.all_damage
                bullet.action.all_damage = true
                begin
                  return maruchi_orig_action_can_hit_target?(bullet, user, skill, tar_invu)
                ensure
                  bullet.action.all_damage = prev_all
                end
              end
              maruchi_orig_action_can_hit_target?(bullet, user, skill, tar_invu)
            end
          end
        end
      end

      Game_Event.class_eval do
        if method_defined?(:check_event_trigger_touch) && !method_defined?(:maruchi_orig_ev_touch)
          alias_method :maruchi_orig_ev_touch, :check_event_trigger_touch
          def check_event_trigger_touch(x, y)
            srv = $MARUCHI_SERVER
            if srv && !srv.sessions.empty? && self.collision_attack && self.battler != nil && !self.battler.dead?
              return if $game_map.interpreter.running?
              srv.sessions.each_value do |s|
                next unless s.alive?
                if x == s.x && y == s.y
                  srv.with_session_context(s) { s.player_obj.attack_effect(self) }
                end
              end
              return
            end
            maruchi_orig_ev_touch(x, y)
          end
        end

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
                owner_sess = srv.session_for_player_obj(@action.user)
                if owner_sess
                  srv.with_session_context(owner_sess) { maruchi_orig_update }
                  return
                end
              end
            end
            maruchi_orig_update
          end
        end
      end

      Game_Character.class_eval do
        if method_defined?(:blow) && !method_defined?(:maruchi_orig_blow)
          alias_method :maruchi_orig_blow, :blow
          def blow(d, power = 1)
            srv = $MARUCHI_SERVER
            if srv && respond_to?(:maruchi_session_id) && maruchi_session_id
              srv.record_player_knockback(maruchi_session_id, d, power)
              @knock_back_duration = XAS_BA::DEFAULT_KNOCK_BACK_DURATION if defined?(XAS_BA)
              return
            end
            maruchi_orig_blow(d, power)
          end
        end

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

        if method_defined?(:execute_actor_defeated_process) && !method_defined?(:maruchi_orig_actor_defeated)
          alias_method :maruchi_orig_actor_defeated, :execute_actor_defeated_process
          def execute_actor_defeated_process
            return if $MARUCHI_SERVER
            maruchi_orig_actor_defeated
          end
        end
      end

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

    def send_world_state_to(session)
      sw_ids = []
      sw_data = $game_switches.instance_variable_get(:@data)
      if sw_data.is_a?(Array)
        sw_data.each_with_index { |v, i| sw_ids << i if i > 0 && v }
      end

      var_pairs = []
      var_data = $game_variables.instance_variable_get(:@data)
      if var_data.is_a?(Array)
        var_data.each_with_index { |v, i| var_pairs << [i, v.to_i] if i > 0 && v.to_i != 0 }
      end

      ssw_entries = []
      ssw_data = $game_self_switches.instance_variable_get(:@data)
      if ssw_data.is_a?(Hash)
        ssw_data.each do |key, v|
          next unless key.is_a?(Array) && key.length >= 3 && key[0].to_i == @map_id
          ssw_entries << [key[0].to_i, key[1].to_i, key[2].to_s, !!v] if v
        end
      end

      session.queue_frame(Maruchi::Protocol.build_world_sync(sw_ids, var_pairs, ssw_entries))
    end

    def broadcast_dirty_world_state!
      unless @dirty_switches.empty?
        @dirty_switches.each do |sid, val|
          broadcast_frame(Maruchi::Protocol.build_event("SW_SET", sid, val ? 1 : 0))
        end
        @dirty_switches.clear
      end
      unless @dirty_variables.empty?
        @dirty_variables.each do |vid, val|
          broadcast_frame(Maruchi::Protocol.build_event("VAR_SET", vid, val))
        end
        @dirty_variables.clear
      end
      unless @dirty_self_switches.empty?
        @dirty_self_switches.each do |key, val|
          broadcast_frame(Maruchi::Protocol.build_event("SSW_SET", key[0].to_i, key[1].to_i, key[2].to_s, val ? 1 : 0))
        end
        @dirty_self_switches.clear
      end
    end

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
      session.refresh_vitals!
    end

    def collect_and_broadcast_fx!(authed_sessions)
      @pending_dead_enemies.each do |ev_id, enemy_id, exp, gold|
        broadcast_frame(Maruchi::Protocol.build_event("ENEMY_DEAD", ev_id, enemy_id, exp, gold))
      end

      @pending_knockbacks.each do |pid, dir, power|
        broadcast_frame(Maruchi::Protocol.build_event("KNOCKBACK", pid, dir, power))
      end

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
        log("Client ##{session.id} HELLO name='#{session.name}' actor=#{session.actor_id} (#{session.actor ? session.actor.name : '?'}) HP=#{session.hp}/#{session.maxhp} MP=#{session.mp}/#{session.maxmp}")
        session.queue_frame(
          Maruchi::Protocol.build_welcome(session.id, @map_id, @spawn_x, @spawn_y, @mode, @tick_rate)
        )
        send_world_state_to(session)
        broadcast_frame(
          Maruchi::Protocol.build_event("JOIN", session.id, session.name),
          exclude_id: session.id
        )
        send_snapshot_to(session)

      when "PSTATE"
        return if fields.length < 13
        return if session.downed?
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
        session.pattern = fields[13].to_i if fields.length > 13
        session.step_anime = (fields[14].to_i != 0) if fields.length > 14
        session.sync_player_obj!

      when "ACTION"
        return unless session.alive?
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
              $game_player.shoot(action_id)
              session.refresh_vitals!
            rescue StandardError => e
              log("WARN shoot error for player ##{session.id} (action=#{action_id}): #{e.class}: #{e.message}")
            end
          end
        end
        broadcast_frame(
          Maruchi::Protocol.build_event("ACTION", session.id, kind, action_id, session.dir),
          exclude_id: session.id
        )

      when "REQ_ACTOR"
        aid = fields[1].to_i
        if aid > 0 && $data_actors && $data_actors[aid]
          session.set_actor!(aid)
          aname = $data_actors[aid].name.to_s
          log("Player ##{session.id} switched actor to ##{aid} ('#{aname}') HP=#{session.hp}/#{session.maxhp}")
          broadcast_frame(Maruchi::Protocol.build_event("ACTOR_CHANGED", session.id, aid, aname))
          broadcast_snapshot!
        end

      when "REQ_TRANSFER"
        mid  = fields[1].to_i
        tx   = fields.length > 2 ? fields[2].to_i : -1
        ty   = fields.length > 3 ? fields[3].to_i : -1
        tdir = fields.length > 4 ? fields[4].to_i : 2
        log("Player ##{session.id} requested transfer to Map ##{mid} (#{tx},#{ty})")
        queue_map_transfer(mid, tx, ty, tdir)

      when "REQ_MODE"
        new_mode = Maruchi::Protocol.unesc(fields[1])
        log("Player ##{session.id} requested mode '#{new_mode}'")
        switch_mode!(new_mode)

      when "REQ_INTERACT"
        return unless session.alive?
        ix   = fields[1].to_i
        iy   = fields[2].to_i
        idir = fields[3].to_i
        session.x = ix if ix >= 0 && ix < $game_map.width
        session.y = iy if iy >= 0 && iy < $game_map.height
        session.dir = idir if [2, 4, 6, 8].include?(idir)
        with_session_context(session) do
          begin
            po = session.player_obj
            po.check_event_trigger_here([0, 1, 2]) if po.respond_to?(:check_event_trigger_here)
            po.check_event_trigger_there([0, 1, 2]) if po.respond_to?(:check_event_trigger_there)
          rescue StandardError => e
            log("WARN interact error for player ##{session.id}: #{e.class}: #{e.message}")
          end
        end

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
