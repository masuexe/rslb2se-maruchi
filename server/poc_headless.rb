# frozen_string_literal: false

#==============================================================================
# Step 2 PoC: Cross-Platform Headless RGSS2 + XAS Runtime Verification
# Works identically on Windows and Linux (WSL):
#   ruby server/poc_headless.rb [game_dir] [map_id] [frames]
#==============================================================================

require_relative "rgss2/runtime"

repo_root = File.expand_path("..", __dir__)
game_dir  = ARGV[0] || File.join(repo_root, "game")
test_map  = (ARGV[1] || 116).to_i
frames    = (ARGV[2] || 180).to_i

puts "=== Maruchi Headless RGSS2 PoC ==="
puts "Platform : #{RUBY_PLATFORM} (Ruby #{RUBY_VERSION})"
puts "Game dir : #{game_dir}"

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
rt = Maruchi::HeadlessRuntime.boot!(game_dir: game_dir, verbose: true)
t_scripts = Process.clock_gettime(Process::CLOCK_MONOTONIC)

puts format("Scripts  : loaded=%d skipped=%d failed=%d (%.1f ms)",
            rt.loaded_scripts.size, rt.skipped_scripts.size, rt.failed_scripts.size,
            (t_scripts - t0) * 1000.0)
raise "Expected 0 failed scripts, got #{rt.failed_scripts.size}" unless rt.failed_scripts.empty?

puts "\n=== Loading RMVX Databases ==="
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

t_db = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts format("DB loaded: actors=%d enemies=%d skills=%d weapons=%d common_events=%d maps=%d (%.1f ms)",
            $data_actors.compact.size,
            $data_enemies.compact.size,
            $data_skills.compact.size,
            $data_weapons.compact.size,
            $data_common_events.compact.size,
            $data_mapinfos.size,
            (t_db - t_scripts) * 1000.0)

puts "\n=== Initializing Game World & Combat Map ##{test_map} ==="
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
$game_map.setup(test_map)

target_enemy = $game_map.events.values.find { |e| e.respond_to?(:battler) && e.battler.is_a?(Game_Enemy) }
raise "No XAS Game_Enemy found on Map ##{test_map}" unless target_enemy

start_x = [target_enemy.x - 1, 1].max
start_y = target_enemy.y
$game_player.moveto(start_x, start_y)
$game_player.turn_right
$game_player.refresh

enemy_hp_before = target_enemy.battler.hp
enemy_initial_pos = {}
$game_map.events.each do |id, ev|
  if ev.respond_to?(:battler) && ev.battler.is_a?(Game_Enemy)
    enemy_initial_pos[id] = [ev.x, ev.y]
  end
end

puts format("Map #%d ready: %dx%d events=%d enemies=%d leader=%s",
            $game_map.map_id, $game_map.width, $game_map.height,
            $game_map.events.size, enemy_initial_pos.size, $game_party.members.first.name)
puts format("Target enemy #%d (%s) at (%d,%d), HP=%d",
            target_enemy.id, target_enemy.battler.name, target_enemy.x, target_enemy.y, enemy_hp_before)

puts "\n=== Running #{frames} Headless Combat Ticks ==="
# Fire XAS weapon at frame 0 towards target_enemy, then walk down for 60 frames
$game_player.shoot(1)

t_sim_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
frames.times do |f|
  Graphics.update
  if f >= 20 && f < 80
    Input.set_state(pressed: { Input::DOWN => true })
  else
    Input.clear!
  end
  $game_system.update
  $game_map.update
  $game_player.update
end
t_sim_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

elapsed_ms = (t_sim_end - t_sim_start) * 1000.0
moved_enemies = enemy_initial_pos.count do |id, (ix, iy)|
  ev = $game_map.events[id]
  ev && (ev.x != ix || ev.y != iy)
end
enemy_hp_after = target_enemy.battler.hp
player_moved = ($game_player.x != start_x || $game_player.y != start_y)

puts format("Completed %d ticks in %.2f ms (%.3f ms/tick, ~%.0f ticks/sec)",
            frames, elapsed_ms, elapsed_ms / frames, frames / (t_sim_end - t_sim_start))
puts format("Check 1 [Player Input Move] : (%d,%d) -> (%d,%d) [%s]",
            start_x, start_y, $game_player.x, $game_player.y, player_moved ? "PASS" : "FAIL")
puts format("Check 2 [XAS Weapon Damage] : Enemy #%d HP %d -> %d [%s]",
            target_enemy.id, enemy_hp_before, enemy_hp_after, enemy_hp_after < enemy_hp_before ? "PASS" : "FAIL")
puts format("Check 3 [XAS Enemy AI Move] : %d/%d enemies actively moved [%s]",
            moved_enemies, enemy_initial_pos.size, moved_enemies > 0 ? "PASS" : "FAIL")

unless player_moved && enemy_hp_after < enemy_hp_before && moved_enemies > 0
  raise "One or more headless combat checks failed!"
end

puts "\nALL HEADLESS RGSS2 + XAS CHECKS PASSED!"
