# frozen_string_literal: false

require "zlib"
require_relative "ruby18_compat"
require_relative "primitives"
require_relative "rpg"
require_relative "headless_stubs"

module Maruchi
  module HeadlessRuntime
    # Scripts that are strictly Windows-only tooling, HTTP ranking, video playback, or GUI entrypoint.
    SKIP_SCRIPT_PATTERNS = [
      /\AMain\z/i,
      /\A▼ Maruchi Loader\z/,
      /AsHttp/i,
      /AsNetwork/i,
      /RankingApi/i,
      /RankingProvider/i,
      /VersionCheckApi/i,
      /RMzas分数上传API/,
      /打开网页/,
      /RMTV for VX/i,
      /删除存档/
    ].freeze

    class << self
      attr_reader :loaded_scripts, :skipped_scripts, :failed_scripts

      def boot!(game_dir:, scripts_rvdata: nil, verbose: false)
        @game_dir = File.expand_path(game_dir)
        @scripts_rvdata = scripts_rvdata || default_scripts_path(@game_dir)
        @loaded_scripts  = []
        @skipped_scripts = []
        @failed_scripts  = []

        Dir.chdir(@game_dir)

        # Ensure $TEST / $DEBUG are false so Win32 debug console (script 000) does not activate
        $TEST  = false
        $DEBUG = false
        $BTEST = false
        $MARUCHI_HEADLESS = true

        raw_entries = File.open(@scripts_rvdata, "rb") { |f| Marshal.load(f) }
        raw_entries.each_with_index do |entry, idx|
          _id, title_raw, zcode = entry
          title = title_raw.to_s.dup.force_encoding(Encoding::UTF_8)
          code  = zcode && !zcode.empty? ? Zlib::Inflate.inflate(zcode).force_encoding(Encoding::UTF_8) : ""

          if idx == 0 || skip_script?(title)
            @skipped_scripts << [idx, title]
            next
          end
          next if code.strip.empty?

          begin
            eval(code, TOPLEVEL_BINDING, format("Section%03d:%s", idx, title), 1)
            @loaded_scripts << [idx, title]
          rescue Exception => e
            @failed_scripts << [idx, title, e]
            warn(format("[FAIL] Section%03d (%s): %s: %s", idx, title, e.class, e.message))
            if verbose && e.backtrace
              e.backtrace.first(5).each { |bt| warn("         #{bt}") }
            end
          end
        end

        self
      end

      private

      def default_scripts_path(dir)
        orig = File.join(dir, "Data", "Scripts.rvdata.orig")
        return orig if File.exist?(orig)
        File.join(dir, "Data", "Scripts.rvdata")
      end

      def skip_script?(title)
        SKIP_SCRIPT_PATTERNS.any? { |pat| pat.match?(title) }
      end
    end
  end
end
