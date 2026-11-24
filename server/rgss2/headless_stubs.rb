# frozen_string_literal: false

#==============================================================================
# RGSS2 Headless Stubs: Graphics, Input, Audio, Font, Bitmap, Sprite,
# Viewport, Plane, Tilemap, Window, Win32API, Kernel helpers.
# Runs identically on Linux and Windows without any GUI/display/audio device.
#==============================================================================

module Graphics
  @frame_rate  = 60
  @frame_count = 0
  @brightness  = 255
  @width       = 544
  @height      = 416

  class << self
    attr_accessor :frame_rate, :frame_count, :brightness
    attr_reader :width, :height

    def update
      @frame_count += 1
    end

    def wait(duration)
      @frame_count += duration.to_i
    end

    def fadeout(_duration)
      @brightness = 0
    end

    def fadein(_duration)
      @brightness = 255
    end

    def freeze; end
    def transition(_duration = 10, _filename = "", _vague = 40); end
    def snap_to_bitmap; Bitmap.new(@width, @height); end
    def frame_reset; end
    def resize_screen(w, h); @width = w.to_i; @height = h.to_i; end
    def play_movie(_filename); end
  end
end

module Input
  DOWN  = 2
  LEFT  = 4
  RIGHT = 6
  UP    = 8
  A     = 11
  B     = 12
  C     = 13
  X     = 14
  Y     = 15
  Z     = 16
  L     = 17
  R     = 18
  SHIFT = 21
  CTRL  = 22
  ALT   = 23
  F5    = 25
  F6    = 26
  F7    = 27
  F8    = 28
  F9    = 29

  @pressed   = {}
  @triggered = {}
  @repeated  = {}

  class << self
    def update
      # Virtual input state is driven explicitly by the server per player tick
    end

    def clear!
      @pressed.clear
      @triggered.clear
      @repeated.clear
    end

    def set_state(pressed: {}, triggered: {}, repeated: {})
      @pressed   = pressed
      @triggered = triggered
      @repeated  = repeated
    end

    def press?(btn);   !!@pressed[btn];   end
    def trigger?(btn); !!@triggered[btn]; end
    def repeat?(btn);  !!@repeated[btn];  end

    def dir4
      return DOWN  if press?(DOWN)
      return LEFT  if press?(LEFT)
      return RIGHT if press?(RIGHT)
      return UP    if press?(UP)
      0
    end

    def dir8
      d = press?(DOWN)
      u = press?(UP)
      l = press?(LEFT)
      r = press?(RIGHT)
      return 1 if d && l
      return 3 if d && r
      return 7 if u && l
      return 9 if u && r
      return 2 if d
      return 4 if l
      return 6 if r
      return 8 if u
      0
    end
  end
end

module Audio
  class << self
    def bgm_play(_filename, _volume = 100, _pitch = 100); end
    def bgm_stop; end
    def bgm_fade(_time); end
    def bgs_play(_filename, _volume = 100, _pitch = 100); end
    def bgs_stop; end
    def bgs_fade(_time); end
    def me_play(_filename, _volume = 100, _pitch = 100); end
    def me_stop; end
    def me_fade(_time); end
    def se_play(_filename, _volume = 100, _pitch = 100); end
    def se_stop; end
  end
end

class Font
  @@default_name   = ["SimHei", "Verdana"]
  @@default_size   = 20
  @@default_bold   = false
  @@default_italic = false
  @@default_shadow = true
  @@default_color  = Color.new(255, 255, 255, 255)

  class << self
    def default_name;       @@default_name;       end
    def default_name=(v);   @@default_name = v;   end
    def default_size;       @@default_size;       end
    def default_size=(v);   @@default_size = v;   end
    def default_bold;       @@default_bold;       end
    def default_bold=(v);   @@default_bold = v;   end
    def default_italic;     @@default_italic;     end
    def default_italic=(v); @@default_italic = v; end
    def default_shadow;     @@default_shadow;     end
    def default_shadow=(v); @@default_shadow = v; end
    def default_color;      @@default_color;      end
    def default_color=(v);  @@default_color = v;  end
    def exist?(_name);      true;                 end
  end

  attr_accessor :name, :size, :bold, :italic, :shadow, :color

  def initialize(name = @@default_name, size = @@default_size)
    @name   = name
    @size   = size
    @bold   = @@default_bold
    @italic = @@default_italic
    @shadow = @@default_shadow
    @color  = @@default_color.dup
  end
end

class Bitmap
  attr_reader :width, :height
  attr_accessor :font

  def initialize(*args)
    @disposed = false
    @font = Font.new
    if args.length == 1 && args[0].is_a?(String)
      @filename = args[0]
      @width, @height = probe_image_size(@filename)
    elsif args.length == 2
      @width  = [args[0].to_i, 1].max
      @height = [args[1].to_i, 1].max
    else
      @width  = 32
      @height = 32
    end
  end

  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
  def rect;      Rect.new(0, 0, @width, @height); end
  def blt(*_args); end
  def stretch_blt(*_args); end
  def fill_rect(*_args); end
  def gradient_fill_rect(*_args); end
  def clear; end
  def clear_rect(*_args); end
  def get_pixel(_x, _y); Color.new(0, 0, 0, 0); end
  def set_pixel(_x, _y, _color); end
  def hue_change(_hue); end
  def blur; end
  def radial_blur(_angle, _division); end
  def draw_text(*_args); end

  def text_size(str)
    s = str.to_s
    Rect.new(0, 0, [s.length * (@font.size / 2), 1].max, @font.size)
  end

  private

  # Read PNG IHDR dimensions if the file exists on disk so any layout/character-sheet math gets real dimensions.
  def probe_image_size(path)
    candidates = [path, "#{path}.png", "#{path}.PNG", "#{path}.jpg", "#{path}.bmp"]
    candidates.each do |c|
      next unless File.file?(c)
      header = File.binread(c, 24)
      if header && header.bytesize >= 24 && header.byteslice(0, 8) == "\x89PNG\r\n\x1A\n".b
        w, h = header.byteslice(16, 8).unpack("NN")
        return [[w, 1].max, [h, 1].max]
      end
    end
    [32, 32]
  rescue StandardError
    [32, 32]
  end
end

class Viewport
  attr_accessor :rect, :visible, :z, :ox, :oy, :color, :tone

  def initialize(*args)
    @disposed = false
    @rect = case args.length
            when 1 then args[0].is_a?(Rect) ? args[0].dup : Rect.new(0, 0, 544, 416)
            when 4 then Rect.new(*args)
            else Rect.new(0, 0, 544, 416)
            end
    @visible = true
    @z = 0
    @ox = 0
    @oy = 0
    @color = Color.new(0, 0, 0, 0)
    @tone  = Tone.new(0, 0, 0, 0)
  end

  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
  def flash(_color, _duration); end
  def update; end
end

class Sprite
  attr_accessor :bitmap, :src_rect, :viewport, :visible, :x, :y, :z
  attr_accessor :ox, :oy, :zoom_x, :zoom_y, :angle, :wave_amp, :wave_length
  attr_accessor :wave_speed, :wave_phase, :mirror, :bush_depth, :bush_opacity
  attr_accessor :opacity, :blend_type, :color, :tone

  def initialize(viewport = nil)
    @disposed = false
    @viewport = viewport
    @bitmap = nil
    @src_rect = Rect.new(0, 0, 0, 0)
    @visible = true
    @x = @y = @z = @ox = @oy = 0
    @zoom_x = @zoom_y = 1.0
    @angle = 0.0
    @wave_amp = @wave_length = @wave_speed = @wave_phase = 0
    @mirror = false
    @bush_depth = 0
    @bush_opacity = 128
    @opacity = 255
    @blend_type = 0
    @color = Color.new(0, 0, 0, 0)
    @tone  = Tone.new(0, 0, 0, 0)
  end

  def bitmap=(b)
    @bitmap = b
    @src_rect = b ? Rect.new(0, 0, b.width, b.height) : Rect.new(0, 0, 0, 0)
  end

  def width;  @src_rect.width;  end
  def height; @src_rect.height; end
  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
  def flash(_color, _duration); end
  def update; end
end

class Plane
  attr_accessor :bitmap, :viewport, :visible, :z, :ox, :oy, :zoom_x, :zoom_y
  attr_accessor :opacity, :blend_type, :color, :tone

  def initialize(viewport = nil)
    @disposed = false
    @viewport = viewport
    @bitmap = nil
    @visible = true
    @z = @ox = @oy = 0
    @zoom_x = @zoom_y = 1.0
    @opacity = 255
    @blend_type = 0
    @color = Color.new(0, 0, 0, 0)
    @tone  = Tone.new(0, 0, 0, 0)
  end

  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
end

class Tilemap
  attr_accessor :bitmaps, :map_data, :flash_data, :passages, :viewport
  attr_accessor :visible, :ox, :oy

  def initialize(viewport = nil)
    @disposed = false
    @viewport = viewport
    @bitmaps = []
    @visible = true
    @ox = @oy = 0
  end

  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
  def update; end
end

class Window
  attr_accessor :windowskin, :contents, :cursor_rect, :viewport, :active
  attr_accessor :visible, :pause, :x, :y, :width, :height, :z, :ox, :oy
  attr_accessor :opacity, :back_opacity, :contents_opacity, :openness

  def initialize(x = 0, y = 0, width = 0, height = 0)
    @disposed = false
    @windowskin = nil
    @contents = Bitmap.new([width - 32, 1].max, [height - 32, 1].max)
    @cursor_rect = Rect.new(0, 0, 0, 0)
    @viewport = nil
    @active = true
    @visible = true
    @pause = false
    @x = x
    @y = y
    @width = width
    @height = height
    @z = 100
    @ox = @oy = 0
    @opacity = 255
    @back_opacity = 200
    @contents_opacity = 255
    @openness = 255
  end

  def dispose;   @disposed = true; end
  def disposed?; @disposed;        end
  def update; end
end

unless defined?(Win32API)
  class Win32API
    def initialize(_dll, _func, _import = nil, _export = nil)
    end

    def call(*_args)
      0
    end
  end
end

module Kernel
  def load_data(filename)
    path = filename
    unless File.exist?(path)
      # Case-insensitive fallback for Linux filesystems when RGSS scripts differ in casing
      dir = File.dirname(path)
      base = File.basename(path).downcase
      if File.directory?(dir)
        hit = Dir.entries(dir).find { |e| e.downcase == base }
        path = File.join(dir, hit) if hit
      end
    end
    obj = File.open(path, "rb") { |f| Marshal.load(f) }
    MaruchiEncodingHelper.fix_strings!(obj)
  end

  def save_data(obj, filename)
    File.open(filename, "wb") { |f| Marshal.dump(obj, f) }
  end

  def rgss_main
    yield
  end

  def msgbox(*args)
    puts("[RGSS msgbox] #{args.map(&:to_s).join(' ')}")
  end
end
