#==============================================================================
# Smoke-test Mod: Verifies external script injection & Scene_Title hook
#==============================================================================
if Maruchi::Config::MODS[:banner]
  class Scene_Title
    alias maruchi_banner_start start
    def start
      maruchi_banner_start
      Maruchi::Log.info("Scene_Title started (Maruchi hook active, pid=#{Process.pid rescue 0})")
    end
  end
end
