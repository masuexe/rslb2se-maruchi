#==============================================================================
# Maruchi External Script Loader (RGSS2 / Ruby 1.8.1 compatible)
# Loaded by the tiny bootstrap injected into game/Data/Scripts.rvdata
#==============================================================================
module Maruchi
  VERSION = "0.1.0"
  CLIENT_DIR = File.dirname(File.expand_path($MARUCHI_LOADER_PATH || __FILE__))
  ROOT_DIR = File.expand_path("..", CLIENT_DIR)
  SHARED_DIR = File.join(ROOT_DIR, "shared")
  LOGS_DIR = File.join(ROOT_DIR, "logs")

  module Log
    @file = nil

    def self.init
      return unless Maruchi::Config::LOG_TO_FILE
      begin
        Dir.mkdir(Maruchi::LOGS_DIR) unless File.directory?(Maruchi::LOGS_DIR)
        pid = Process.pid rescue 0
        stamp = Time.now.strftime("%Y%m%d_%H%M%S")
        path = File.join(Maruchi::LOGS_DIR, "client_#{stamp}_#{pid}.log")
        @file = File.open(path, "wb")
        @file.sync = true
      rescue Exception
        @file = nil
      end
    end

    def self.write(level, msg)
      ts = Time.now.strftime("%H:%M:%S")
      line = "[#{ts}][#{level}] #{msg}"
      if @file
        begin
          @file.write(line + "\n")
        rescue Exception
        end
      end
      if Maruchi::Config::LOG_TO_CONSOLE
        begin
          puts(line) if ($TEST || $DEBUG)
        rescue Exception
        end
      end
    end

    def self.info(msg);  write("INFO", msg);  end
    def self.warn(msg);  write("WARN", msg);  end
    def self.error(msg); write("ERROR", msg); end
  end

  module Loader
    def self.eval_file(path)
      src = File.open(path, "rb") { |f| f.read }
      eval(src, TOPLEVEL_BINDING, path, 1)
    end

    def self.load_file(path)
      Maruchi::Log.info("Loading #{path}")
      eval_file(path)
    end

    def self.load_dir(dir)
      return unless File.directory?(dir)
      files = Dir.glob(File.join(dir, "*.rb")).sort
      files.each do |file|
        begin
          load_file(file)
        rescue Exception => e
          Maruchi::Log.error("Failed to load #{file}: #{e.class}: #{e.message}")
          bt = (e.backtrace || [])[0, 10]
          bt.each { |line| Maruchi::Log.error("  #{line}") }
          raise
        end
      end
    end

    def self.boot
      eval_file(File.join(Maruchi::CLIENT_DIR, "config.rb"))
      Maruchi::Log.init
      Maruchi::Log.info("Maruchi v#{Maruchi::VERSION} booting (Ruby #{RUBY_VERSION}, pwd=#{Dir.pwd})")
      if defined?(Maruchi::Config::INI_PATH) && Maruchi::Config::INI_PATH
        Maruchi::Log.info("Loaded config from #{Maruchi::Config::INI_PATH} (host=#{Maruchi::Config::SERVER_HOST}:#{Maruchi::Config::SERVER_PORT}, name=#{Maruchi::Config::PLAYER_NAME})")
      end
      load_dir(Maruchi::SHARED_DIR)
      load_dir(File.join(Maruchi::CLIENT_DIR, "core"))
      load_dir(File.join(Maruchi::CLIENT_DIR, "mods"))
      Maruchi::Log.info("Maruchi external scripts loaded successfully.")
    end
  end
end

Maruchi::Loader.boot
