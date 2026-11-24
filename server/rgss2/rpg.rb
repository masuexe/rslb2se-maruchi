# frozen_string_literal: false

#==============================================================================
# RGSS2 (RPG Maker VX) Standard RPG:: Data Classes (Headless-safe)
#==============================================================================

module RPG
  class Map
    def initialize(width = 20, height = 15)
      @width = width
      @height = height
      @scroll_type = 0
      @autoplay_bgm = false
      @bgm = RPG::AudioFile.new
      @autoplay_bgs = false
      @bgs = RPG::AudioFile.new("", 80)
      @disable_dashing = false
      @encounter_list = []
      @encounter_step = 30
      @parallax_name = ""
      @parallax_loop_x = false
      @parallax_loop_y = false
      @parallax_sx = 0
      @parallax_sy = 0
      @parallax_show = false
      @data = Table.new(width, height, 3)
      @events = {}
    end
    attr_accessor :width, :height, :scroll_type, :autoplay_bgm, :bgm
    attr_accessor :autoplay_bgs, :bgs, :disable_dashing, :encounter_list, :encounter_step
    attr_accessor :parallax_name, :parallax_loop_x, :parallax_loop_y
    attr_accessor :parallax_sx, :parallax_sy, :parallax_show, :data, :events
  end

  class MapInfo
    def initialize
      @name = ""
      @parent_id = 0
      @order = 0
      @expanded = false
      @scroll_x = 0
      @scroll_y = 0
    end
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end

  class Area
    def initialize
      @id = 0
      @name = ""
      @map_id = 0
      @rect = Rect.new(0, 0, 0, 0)
      @encounter_list = []
      @order = 0
    end
    attr_accessor :id, :name, :map_id, :rect, :encounter_list, :order
  end

  class Event
    def initialize(x = 0, y = 0)
      @id = 0
      @name = ""
      @x = x
      @y = y
      @pages = [RPG::Event::Page.new]
    end
    attr_accessor :id, :name, :x, :y, :pages

    class Page
      def initialize
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @move_type = 0
        @move_speed = 3
        @move_frequency = 3
        @move_route = RPG::MoveRoute.new
        @walk_anime = true
        @step_anime = false
        @direction_fix = false
        @through = false
        @priority_type = 0
        @trigger = 0
        @list = [RPG::EventCommand.new]
      end
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency
      attr_accessor :move_route, :walk_anime, :step_anime, :direction_fix
      attr_accessor :through, :priority_type, :trigger, :list

      class Condition
        def initialize
          @switch1_valid = false
          @switch2_valid = false
          @variable_valid = false
          @self_switch_valid = false
          @item_valid = false
          @actor_valid = false
          @switch1_id = 1
          @switch2_id = 1
          @variable_id = 1
          @variable_value = 0
          @self_switch_ch = "A"
          @item_id = 1
          @actor_id = 1
        end
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid
        attr_accessor :self_switch_valid, :item_valid, :actor_valid
        attr_accessor :switch1_id, :switch2_id, :variable_id, :variable_value
        attr_accessor :self_switch_ch, :item_id, :actor_id
      end

      class Graphic
        def initialize
          @tile_id = 0
          @character_name = ""
          @character_index = 0
          @direction = 2
          @pattern = 0
        end
        attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern
      end
    end
  end

  class EventCommand
    def initialize(code = 0, indent = 0, parameters = [])
      @code = code
      @indent = indent
      @parameters = parameters
    end
    attr_accessor :code, :indent, :parameters
  end

  class MoveRoute
    def initialize
      @repeat = true
      @skippable = false
      @wait = false
      @list = [RPG::MoveCommand.new]
    end
    attr_accessor :repeat, :skippable, :wait, :list
  end

  class MoveCommand
    def initialize(code = 0, parameters = [])
      @code = code
      @parameters = parameters
    end
    attr_accessor :code, :parameters
  end

  class BaseItem
    def initialize
      @id = 0
      @name = ""
      @icon_index = 0
      @description = ""
      @note = ""
    end
    attr_accessor :id, :name, :icon_index, :description, :note
  end

  class UsableItem < BaseItem
    def initialize
      super
      @scope = 0
      @occasion = 0
      @speed = 0
      @animation_id = 0
      @common_event_id = 0
      @base_damage = 0
      @variance = 20
      @atk_f = 0
      @spi_f = 0
      @physical_attack = false
      @damage_to_mp = false
      @absorb_damage = false
      @ignore_defense = false
      @element_set = []
      @plus_state_set = []
      @minus_state_set = []
    end
    def for_opponent?; [1, 2, 3, 4, 5, 6].include?(@scope); end
    def for_friend?;   [7, 8, 9, 10, 11].include?(@scope); end
    def for_dead_friend?; [9, 10].include?(@scope); end
    def for_user?;     @scope == 11; end
    def for_one?;      [1, 3, 4, 7, 9, 11].include?(@scope); end
    def for_two?;      @scope == 5; end
    def for_three?;    @scope == 6; end
    def for_random?;   [4, 5, 6].include?(@scope); end
    def for_all?;      [2, 8, 10].include?(@scope); end
    def dual?;         @scope == 3; end
    def need_selection?; [1, 3, 7, 9].include?(@scope); end
    def battle_ok?;    [0, 1].include?(@occasion); end
    def menu_ok?;      [0, 2].include?(@occasion); end
    attr_accessor :scope, :occasion, :speed, :animation_id, :common_event_id
    attr_accessor :base_damage, :variance, :atk_f, :spi_f
    attr_accessor :physical_attack, :damage_to_mp, :absorb_damage, :ignore_defense
    attr_accessor :element_set, :plus_state_set, :minus_state_set
  end

  class Actor
    def initialize
      @id = 0
      @name = ""
      @class_id = 1
      @initial_level = 1
      @exp_basis = 25
      @exp_inflation = 35
      @character_name = ""
      @character_index = 0
      @face_name = ""
      @face_index = 0
      @parameters = Table.new(6, 100)
      @weapon_id = 0
      @armor1_id = 0
      @armor2_id = 0
      @armor3_id = 0
      @armor4_id = 0
      @two_swords_style = false
      @fix_equipment = false
      @auto_battle = false
      @super_guard = false
      @pharmacology = false
      @critical_bonus = false
    end
    attr_accessor :id, :name, :class_id, :initial_level, :exp_basis, :exp_inflation
    attr_accessor :character_name, :character_index, :face_name, :face_index
    attr_accessor :parameters, :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    attr_accessor :two_swords_style, :fix_equipment, :auto_battle, :super_guard
    attr_accessor :pharmacology, :critical_bonus
  end

  class Class
    def initialize
      @id = 0
      @name = ""
      @position = 0
      @weapon_set = []
      @armor_set = []
      @element_ranks = Table.new(1)
      @state_ranks = Table.new(1)
      @learnings = []
      @skill_name_valid = false
      @skill_name = ""
    end
    attr_accessor :id, :name, :position, :weapon_set, :armor_set
    attr_accessor :element_ranks, :state_ranks, :learnings
    attr_accessor :skill_name_valid, :skill_name

    class Learning
      def initialize
        @level = 1
        @skill_id = 1
      end
      attr_accessor :level, :skill_id
    end
  end

  class Skill < UsableItem
    def initialize
      super
      @scope = 1
      @mp_cost = 0
      @hit = 100
      @message1 = ""
      @message2 = ""
    end
    attr_accessor :mp_cost, :hit, :message1, :message2
  end

  class Item < UsableItem
    def initialize
      super
      @scope = 7
      @price = 0
      @consumable = true
      @hp_recovery_rate = 0
      @hp_recovery = 0
      @mp_recovery_rate = 0
      @mp_recovery = 0
      @parameter_type = 0
      @parameter_points = 0
    end
    attr_accessor :price, :consumable, :hp_recovery_rate, :hp_recovery
    attr_accessor :mp_recovery_rate, :mp_recovery, :parameter_type, :parameter_points
  end

  class Weapon < BaseItem
    def initialize
      super
      @animation_id = 0
      @price = 0
      @hit = 95
      @atk = 0
      @def = 0
      @spi = 0
      @agi = 0
      @two_handed = false
      @fast_attack = false
      @dual_attack = false
      @critical_bonus = false
      @element_set = []
      @state_set = []
    end
    attr_accessor :animation_id, :price, :hit, :atk, :def, :spi, :agi
    attr_accessor :two_handed, :fast_attack, :dual_attack, :critical_bonus
    attr_accessor :element_set, :state_set
  end

  class Armor < BaseItem
    def initialize
      super
      @kind = 0
      @price = 0
      @eva = 0
      @atk = 0
      @def = 0
      @spi = 0
      @agi = 0
      @prevent_critical = false
      @half_mp_cost = false
      @double_exp_gain = false
      @auto_hp_recover = false
      @element_set = []
      @state_set = []
    end
    attr_accessor :kind, :price, :eva, :atk, :def, :spi, :agi
    attr_accessor :prevent_critical, :half_mp_cost, :double_exp_gain, :auto_hp_recover
    attr_accessor :element_set, :state_set
  end

  class Enemy
    def initialize
      @id = 0
      @name = ""
      @battler_name = ""
      @battler_hue = 0
      @maxhp = 10
      @maxmp = 10
      @atk = 10
      @def = 10
      @spi = 10
      @agi = 10
      @hit = 95
      @eva = 5
      @exp = 0
      @gold = 0
      @drop_item1 = RPG::Enemy::DropItem.new
      @drop_item2 = RPG::Enemy::DropItem.new
      @levitate = false
      @has_critical = false
      @element_ranks = Table.new(1)
      @state_ranks = Table.new(1)
      @actions = [RPG::Enemy::Action.new]
      @note = ""
    end
    attr_accessor :id, :name, :battler_name, :battler_hue
    attr_accessor :maxhp, :maxmp, :atk, :def, :spi, :agi, :hit, :eva
    attr_accessor :exp, :gold, :drop_item1, :drop_item2
    attr_accessor :levitate, :has_critical, :element_ranks, :state_ranks
    attr_accessor :actions, :note

    class DropItem
      def initialize
        @kind = 0
        @item_id = 1
        @weapon_id = 1
        @armor_id = 1
        @denominator = 1
      end
      attr_accessor :kind, :item_id, :weapon_id, :armor_id, :denominator
    end

    class Action
      def initialize
        @kind = 0
        @basic = 0
        @skill_id = 1
        @condition_type = 0
        @condition_param1 = 0
        @condition_param2 = 0
        @rating = 5
      end
      def skill?; @kind == 1; end
      attr_accessor :kind, :basic, :skill_id, :condition_type
      attr_accessor :condition_param1, :condition_param2, :rating
    end
  end

  class State
    def initialize
      @id = 0
      @name = ""
      @icon_index = 0
      @restriction = 0
      @priority = 5
      @atk_rate = 100
      @def_rate = 100
      @spi_rate = 100
      @agi_rate = 100
      @nonresistance = false
      @offset_by_opposite = false
      @slip_damage = false
      @reduce_hit_ratio = false
      @battle_only = true
      @release_by_damage = false
      @hold_turn = 0
      @auto_release_prob = 0
      @message1 = ""
      @message2 = ""
      @message3 = ""
      @message4 = ""
      @element_set = []
      @state_set = []
      @note = ""
    end
    attr_accessor :id, :name, :icon_index, :restriction, :priority
    attr_accessor :atk_rate, :def_rate, :spi_rate, :agi_rate
    attr_accessor :nonresistance, :offset_by_opposite, :slip_damage, :reduce_hit_ratio
    attr_accessor :battle_only, :release_by_damage, :hold_turn, :auto_release_prob
    attr_accessor :message1, :message2, :message3, :message4
    attr_accessor :element_set, :state_set, :note
  end

  class Troop
    def initialize
      @id = 0
      @name = ""
      @members = []
      @pages = [RPG::Troop::Page.new]
    end
    attr_accessor :id, :name, :members, :pages

    class Member
      def initialize
        @enemy_id = 1
        @x = 0
        @y = 0
        @hidden = false
        @immortal = false
      end
      attr_accessor :enemy_id, :x, :y, :hidden, :immortal
    end

    class Page
      def initialize
        @condition = RPG::Troop::Page::Condition.new
        @span = 0
        @list = [RPG::EventCommand.new]
      end
      attr_accessor :condition, :span, :list

      class Condition
        def initialize
          @turn_ending = false
          @turn_valid = false
          @enemy_valid = false
          @actor_valid = false
          @switch_valid = false
          @turn_a = 0
          @turn_b = 0
          @enemy_index = 0
          @enemy_hp = 50
          @actor_id = 1
          @actor_hp = 50
          @switch_id = 1
        end
        attr_accessor :turn_ending, :turn_valid, :enemy_valid, :actor_valid, :switch_valid
        attr_accessor :turn_a, :turn_b, :enemy_index, :enemy_hp, :actor_id, :actor_hp, :switch_id
      end
    end
  end

  class Animation
    def initialize
      @id = 0
      @name = ""
      @animation1_name = ""
      @animation1_hue = 0
      @animation2_name = ""
      @animation2_hue = 0
      @position = 1
      @frame_max = 1
      @frames = [RPG::Animation::Frame.new]
      @timings = []
    end
    attr_accessor :id, :name, :animation1_name, :animation1_hue
    attr_accessor :animation2_name, :animation2_hue, :position
    attr_accessor :frame_max, :frames, :timings

    class Frame
      def initialize
        @cell_max = 0
        @cell_data = Table.new(0, 0)
      end
      attr_accessor :cell_max, :cell_data
    end

    class Timing
      def initialize
        @frame = 0
        @se = RPG::AudioFile.new("", 80)
        @flash_scope = 0
        @flash_color = Color.new(255, 255, 255, 255)
        @flash_duration = 5
      end
      attr_accessor :frame, :se, :flash_scope, :flash_color, :flash_duration
    end
  end

  class CommonEvent
    def initialize
      @id = 0
      @name = ""
      @trigger = 0
      @switch_id = 1
      @list = [RPG::EventCommand.new]
    end
    attr_accessor :id, :name, :trigger, :switch_id, :list
  end

  class System
    def initialize
      @game_title = ""
      @version_id = 0
      @party_members = [1]
      @elements = [nil, ""]
      @switches = [nil, ""]
      @variables = [nil, ""]
      @passages = Table.new(8192)
      @boat = RPG::System::Vehicle.new
      @ship = RPG::System::Vehicle.new
      @airship = RPG::System::Vehicle.new
      @title_bgm = RPG::BGM.new
      @battle_bgm = RPG::BGM.new
      @battle_end_me = RPG::ME.new
      @gameover_me = RPG::ME.new
      @sounds = []
      @test_battlers = []
      @test_troop_id = 1
      @start_map_id = 1
      @start_x = 0
      @start_y = 0
      @terms = RPG::System::Terms.new
      @battler_name = ""
      @battler_hue = 0
      @edit_map_id = 1
    end
    attr_accessor :game_title, :version_id, :party_members, :elements
    attr_accessor :switches, :variables, :passages, :boat, :ship, :airship
    attr_accessor :title_bgm, :battle_bgm, :battle_end_me, :gameover_me
    attr_accessor :sounds, :test_battlers, :test_troop_id
    attr_accessor :start_map_id, :start_x, :start_y, :terms
    attr_accessor :battler_name, :battler_hue, :edit_map_id

    class Vehicle
      def initialize
        @character_name = ""
        @character_index = 0
        @bgm = RPG::AudioFile.new
        @start_map_id = 0
        @start_x = 0
        @start_y = 0
      end
      attr_accessor :character_name, :character_index, :bgm
      attr_accessor :start_map_id, :start_x, :start_y
    end

    class Terms
      def initialize
        @level = ""
        @level_a = ""
        @hp = ""
        @hp_a = ""
        @mp = ""
        @mp_a = ""
        @atk = ""
        @def = ""
        @spi = ""
        @agi = ""
        @weapon = ""
        @armor1 = ""
        @armor2 = ""
        @armor3 = ""
        @armor4 = ""
        @weapon1 = ""
        @weapon2 = ""
        @attack = ""
        @skill = ""
        @guard = ""
        @item = ""
        @equip = ""
        @status = ""
        @save = ""
        @game_end = ""
        @fight = ""
        @escape = ""
        @new_game = ""
        @continue = ""
        @shutdown = ""
        @to_title = ""
        @cancel = ""
        @gold = ""
      end
      attr_accessor :level, :level_a, :hp, :hp_a, :mp, :mp_a
      attr_accessor :atk, :def, :spi, :agi
      attr_accessor :weapon, :armor1, :armor2, :armor3, :armor4, :weapon1, :weapon2
      attr_accessor :attack, :skill, :guard, :item, :equip, :status, :save, :game_end
      attr_accessor :fight, :escape, :new_game, :continue, :shutdown, :to_title, :cancel, :gold
    end

    class TestBattler
      def initialize
        @actor_id = 1
        @level = 1
        @weapon_id = 0
        @armor1_id = 0
        @armor2_id = 0
        @armor3_id = 0
        @armor4_id = 0
      end
      attr_accessor :actor_id, :level, :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
    end
  end

  class AudioFile
    def initialize(name = "", volume = 100, pitch = 100)
      @name = name
      @volume = volume
      @pitch = pitch
    end
    attr_accessor :name, :volume, :pitch
  end

  class BGM < AudioFile
    @@last = BGM.new
    def play
      if @name.nil? || @name.empty?
        Audio.bgm_stop
        @@last = BGM.new
      else
        Audio.bgm_play("Audio/BGM/" + @name, @volume, @pitch)
        @@last = self
      end
    end
    def self.stop
      Audio.bgm_stop
      @@last = BGM.new
    end
    def self.fade(time)
      Audio.bgm_fade(time)
      @@last = BGM.new
    end
    def self.last
      @@last
    end
  end

  class BGS < AudioFile
    @@last = BGS.new
    def play
      if @name.nil? || @name.empty?
        Audio.bgs_stop
        @@last = BGS.new
      else
        Audio.bgs_play("Audio/BGS/" + @name, @volume, @pitch)
        @@last = self
      end
    end
    def self.stop
      Audio.bgs_stop
      @@last = BGS.new
    end
    def self.fade(time)
      Audio.bgs_fade(time)
      @@last = BGS.new
    end
    def self.last
      @@last
    end
  end

  class ME < AudioFile
    def play
      if @name.nil? || @name.empty?
        Audio.me_stop
      else
        Audio.me_play("Audio/ME/" + @name, @volume, @pitch)
      end
    end
    def self.stop
      Audio.me_stop
    end
    def self.fade(time)
      Audio.me_fade(time)
    end
  end

  class SE < AudioFile
    def initialize(name = "", volume = 80, pitch = 100)
      super(name, volume, pitch)
    end
    def play
      Audio.se_play("Audio/SE/" + @name, @volume, @pitch) unless @name.nil? || @name.empty?
    end
    def self.stop
      Audio.se_stop
    end
  end
end
