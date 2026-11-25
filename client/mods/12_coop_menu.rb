#==============================================================================
# Maruchi In-Game Multiplayer Lobby Menu (F8) — Ruby 1.8.1 / RGSS2 compatible
# - Switch Character (all 137 valid actors with sprite preview)
# - Transfer Party to Map (featured combat/boss maps + full map browser)
# - Toggle Room Mode (CO-OP <-> PVP)
# - Connect / Reconnect / Disconnect
# Keeps Maruchi::Coop.update running while open so network never stalls!
#==============================================================================
if Maruchi::Config::MODS[:coop_client]

  class Window_MaruchiActorSelect < Window_Selectable
    def initialize(x, y, width, height)
      super(x, y, width, height)
      @actors = []
      if $data_actors
        $data_actors.each do |a|
          next unless a && a.name && !a.name.strip.empty?
          next unless a.character_name && !a.character_name.strip.empty?
          @actors.push(a)
        end
      end
      @item_max = @actors.size
      @column_max = 1
      create_contents
      refresh
      cur_id = ($game_party && $game_party.members[0]) ? $game_party.members[0].id : 1
      idx = 0
      @actors.each_with_index { |a, i| idx = i if a.id == cur_id }
      self.index = idx
    end

    def selected_actor
      @actors[self.index]
    end

    def refresh
      self.contents.clear
      @actors.each_with_index do |a, i|
        rect = item_rect(i)
        self.contents.font.size = 18
        self.contents.font.color = normal_color
        self.contents.draw_text(rect.x + 4, rect.y, rect.width - 8, rect.height, sprintf("#%03d  %s", a.id, a.name))
      end
    end
  end

  class Window_MaruchiMapSelect < Window_Selectable
    FEATURED_MAP_IDS = [116, 111, 112, 113, 114, 115, 117, 118, 119, 120, 15, 11, 20, 110, 124]

    def initialize(x, y, width, height)
      super(x, y, width, height)
      @maps = []
      seen = {}
      if $data_mapinfos
        FEATURED_MAP_IDS.each do |mid|
          if $data_mapinfos[mid]
            @maps.push([mid, "[*] #{$data_mapinfos[mid].name}"])
            seen[mid] = true
          end
        end
        $data_mapinfos.keys.sort.each do |mid|
          next if seen[mid]
          info = $data_mapinfos[mid]
          next unless info
          @maps.push([mid, info.name.to_s])
        end
      end
      @item_max = @maps.size
      @column_max = 1
      create_contents
      refresh
      cur_mid = ($game_map ? $game_map.map_id : 116)
      idx = 0
      @maps.each_with_index { |m, i| idx = i if m[0] == cur_mid }
      self.index = idx
    end

    def selected_map_id
      pair = @maps[self.index]
      pair ? pair[0] : nil
    end

    def refresh
      self.contents.clear
      @maps.each_with_index do |pair, i|
        rect = item_rect(i)
        self.contents.font.size = 18
        self.contents.font.color = normal_color
        self.contents.draw_text(rect.x + 4, rect.y, rect.width - 8, rect.height, sprintf("Map %03d  %s", pair[0], pair[1]))
      end
    end
  end

  class Scene_MaruchiMenu < Scene_Base
    def start
      super
      create_menu_background
      @help_window = Window_Base.new(0, 0, 544, 56)
      @cmd_window = Window_Command.new(200, [
        "Select Character",
        "Warp Party (Map)",
        "Toggle CO-OP / PVP",
        "Reconnect Server",
        "Disconnect",
        "Close (F8 / Esc)"
      ])
      @cmd_window.x = 16
      @cmd_window.y = 72

      @info_window = Window_Base.new(232, 72, 296, 324)
      @actor_window = Window_MaruchiActorSelect.new(232, 72, 296, 324)
      @actor_window.visible = false
      @actor_window.active = false

      @map_window = Window_MaruchiMapSelect.new(232, 72, 296, 324)
      @map_window.visible = false
      @map_window.active = false

      @sub_mode = :main
      refresh_help
      refresh_info
    end

    def terminate
      super
      dispose_menu_background
      @help_window.dispose  if @help_window
      @cmd_window.dispose   if @cmd_window
      @info_window.dispose  if @info_window
      @actor_window.dispose if @actor_window
      @map_window.dispose   if @map_window
    end

    def refresh_help
      @help_window.contents.clear
      @help_window.contents.font.size = 18
      case @sub_mode
      when :main
        @help_window.contents.draw_text(4, 0, 504, 24, "Maruchi Multiplayer Lobby  |  #{Maruchi::Coop.hud_text}")
      when :actor
        @help_window.contents.draw_text(4, 0, 504, 24, "Select Character (Up/Down, Left/Right = Page, Enter = Pick)")
      when :map
        @help_window.contents.draw_text(4, 0, 504, 24, "Warp Entire Party to Map (Up/Down, Left/Right = Page, Enter = Go)")
      end
    end

    def refresh_info
      @info_window.contents.clear
      @info_window.contents.font.size = 17
      y = 4
      conn = Maruchi::Coop.connected? ? "CONNECTED" : "OFFLINE"
      mode = Maruchi::Coop.server_mode.to_s.upcase
      mid  = $game_map ? $game_map.map_id : 0
      mname = ($data_mapinfos && $data_mapinfos[mid]) ? $data_mapinfos[mid].name : ""
      aname = ($game_party && $game_party.members[0]) ? $game_party.members[0].name : "-"
      lines = [
        "Status: #{conn}",
        "Server: #{Maruchi::Config::SERVER_HOST}:#{Maruchi::Config::SERVER_PORT}",
        "Mode:   #{mode}",
        "Player: #{Maruchi::Config::PLAYER_NAME} (P##{Maruchi::Coop.my_id || '-'})",
        "Actor:  #{aname}",
        "Map:    ##{mid} #{mname}",
        "Online: #{Maruchi::Coop.connected? ? (Maruchi::Coop.remote_players.size + 1) : 0} player(s)",
        "",
        "Shortcuts:",
        "  F7 - Quick Join / Reconnect",
        "  F8 - Open / Close Lobby Menu"
      ]
      lines.each do |ln|
        @info_window.contents.draw_text(4, y, 256, 22, ln)
        y += 24
      end
    end

    def update
      super
      # Keep network ticks alive while lobby menu is open!
      Maruchi::Coop.update
      @help_window.update
      @cmd_window.update
      @info_window.update
      @actor_window.update
      @map_window.update

      if Input.trigger?(Input::F8)
        Sound.play_cancel rescue nil
        $scene = Scene_Map.new
        return
      end

      case @sub_mode
      when :main
        update_main
      when :actor
        update_actor_select
      when :map
        update_map_select
      end
    end

    def update_main
      if Input.trigger?(Input::B)
        Sound.play_cancel rescue nil
        $scene = Scene_Map.new
        return
      end
      if Input.trigger?(Input::C)
        case @cmd_window.index
        when 0 # Select Character
          Sound.play_decision rescue nil
          @sub_mode = :actor
          @cmd_window.active = false
          @info_window.visible = false
          @actor_window.visible = true
          @actor_window.active = true
          refresh_help
        when 1 # Warp Party (Map)
          Sound.play_decision rescue nil
          @sub_mode = :map
          @cmd_window.active = false
          @info_window.visible = false
          @map_window.visible = true
          @map_window.active = true
          refresh_help
        when 2 # Toggle CO-OP / PVP
          Sound.play_decision rescue nil
          next_mode = (Maruchi::Coop.server_mode == "pvp") ? "coop" : "pvp"
          Maruchi::Coop.request_mode(next_mode)
          refresh_help
          refresh_info
        when 3 # Reconnect
          Sound.play_decision rescue nil
          Maruchi::Coop.connect_and_join
          $scene = Scene_Map.new
        when 4 # Disconnect
          Sound.play_cancel rescue nil
          Maruchi::Coop.disconnect
          refresh_help
          refresh_info
        when 5 # Close
          Sound.play_cancel rescue nil
          $scene = Scene_Map.new
        end
      end
    end

    def return_to_main
      Sound.play_cancel rescue nil
      @sub_mode = :main
      @actor_window.visible = false
      @actor_window.active = false
      @map_window.visible = false
      @map_window.active = false
      @info_window.visible = true
      @cmd_window.active = true
      refresh_help
      refresh_info
    end

    def update_actor_select
      if Input.repeat?(Input::RIGHT)
        @actor_window.index = [@actor_window.index + 10, @actor_window.item_max - 1].min
      elsif Input.repeat?(Input::LEFT)
        @actor_window.index = [@actor_window.index - 10, 0].max
      elsif Input.trigger?(Input::B)
        return_to_main
      elsif Input.trigger?(Input::C)
        actor = @actor_window.selected_actor
        if actor
          Sound.play_decision rescue nil
          if Maruchi::Coop.connected?
            Maruchi::Coop.request_actor(actor.id)
          else
            Maruchi::Coop.apply_local_actor_change(actor.id)
          end
          $scene = Scene_Map.new
        end
      end
    end

    def update_map_select
      if Input.repeat?(Input::RIGHT)
        @map_window.index = [@map_window.index + 10, @map_window.item_max - 1].min
      elsif Input.repeat?(Input::LEFT)
        @map_window.index = [@map_window.index - 10, 0].max
      elsif Input.trigger?(Input::B)
        return_to_main
      elsif Input.trigger?(Input::C)
        mid = @map_window.selected_map_id
        if mid
          Sound.play_decision rescue nil
          if Maruchi::Coop.connected?
            Maruchi::Coop.request_transfer(mid, -1, -1, 2)
          elsif $game_map && $game_player
            $game_map.setup(mid)
            $game_player.moveto($game_map.width / 2, $game_map.height / 2)
            $game_player.refresh
          end
          $scene = Scene_Map.new
        end
      end
    end
  end
end
