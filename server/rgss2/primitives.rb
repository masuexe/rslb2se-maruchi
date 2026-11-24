# frozen_string_literal: false

#==============================================================================
# RGSS2 Native Data Primitives: Table, Color, Tone, Rect, RGSSError
# Binary Marshal _load / _dump formats match RGSS202E.dll exactly.
#==============================================================================

class RGSSError < StandardError; end
class RGSSReset < Exception; end unless defined?(RGSSReset)

class Table
  attr_reader :xsize, :ysize, :zsize

  def initialize(xsize, ysize = 1, zsize = 1)
    @dims = if zsize > 1
              3
            elsif ysize > 1
              2
            else
              1
            end
    @xsize = [xsize.to_i, 0].max
    @ysize = [ysize.to_i, 1].max
    @zsize = [zsize.to_i, 1].max
    @data = Array.new(@xsize * @ysize * @zsize, 0)
  end

  def resize(xsize, ysize = 1, zsize = 1)
    nx = [xsize.to_i, 0].max
    ny = [ysize.to_i, 1].max
    nz = [zsize.to_i, 1].max
    new_data = Array.new(nx * ny * nz, 0)
    mx = [@xsize, nx].min
    my = [@ysize, ny].min
    mz = [@zsize, nz].min
    mz.times do |z|
      my.times do |y|
        mx.times do |x|
          new_data[x + y * nx + z * nx * ny] = @data[x + y * @xsize + z * @xsize * @ysize]
        end
      end
    end
    @xsize = nx
    @ysize = ny
    @zsize = nz
    @data = new_data
    self
  end

  def [](x, y = 0, z = 0)
    xi = x.to_i
    yi = y.to_i
    zi = z.to_i
    return nil if xi < 0 || xi >= @xsize || yi < 0 || yi >= @ysize || zi < 0 || zi >= @zsize
    @data[xi + yi * @xsize + zi * @xsize * @ysize]
  end

  def []=(*args)
    case args.length
    when 2
      x, val = args
      y = 0
      z = 0
    when 3
      x, y, val = args
      z = 0
    when 4
      x, y, z, val = args
    else
      raise ArgumentError, "wrong number of arguments (#{args.length} for 2..4)"
    end
    xi = x.to_i
    yi = y.to_i
    zi = z.to_i
    return val if xi < 0 || xi >= @xsize || yi < 0 || yi >= @ysize || zi < 0 || zi >= @zsize
    # Wrap to signed 16-bit integer like RGSS2
    v = val.to_i & 0xFFFF
    v -= 0x10000 if v >= 0x8000
    @data[xi + yi * @xsize + zi * @xsize * @ysize] = v
  end

  def _dump(_limit)
    header = [@dims, @xsize, @ysize, @zsize, @data.length].pack("V5")
    header + @data.pack("s<*")
  end

  def self._load(str)
    dims, xsize, ysize, zsize, total = str.unpack("V5")
    t = allocate
    t.instance_variable_set(:@dims, dims)
    t.instance_variable_set(:@xsize, xsize)
    t.instance_variable_set(:@ysize, ysize)
    t.instance_variable_set(:@zsize, zsize)
    body = str.byteslice(20, total * 2) || ""
    data = body.unpack("s<*")
    data.fill(0, data.length...total) if data.length < total
    t.instance_variable_set(:@data, data)
    t
  end
end

class Color
  attr_reader :red, :green, :blue, :alpha

  def initialize(red = 0.0, green = 0.0, blue = 0.0, alpha = 255.0)
    set(red, green, blue, alpha)
  end

  def set(red, green = nil, blue = nil, alpha = 255.0)
    if red.is_a?(Color)
      @red   = red.red
      @green = red.green
      @blue  = red.blue
      @alpha = red.alpha
    else
      self.red   = red
      self.green = green
      self.blue  = blue
      self.alpha = alpha
    end
    self
  end

  def red=(v);   @red   = clamp255(v); end
  def green=(v); @green = clamp255(v); end
  def blue=(v);  @blue  = clamp255(v); end
  def alpha=(v); @alpha = clamp255(v); end

  def ==(other)
    other.is_a?(Color) && @red == other.red && @green == other.green && @blue == other.blue && @alpha == other.alpha
  end

  def _dump(_limit)
    [@red, @green, @blue, @alpha].pack("E4")
  end

  def self._load(str)
    r, g, b, a = str.unpack("E4")
    new(r, g, b, a)
  end

  private

  def clamp255(v)
    f = v.to_f
    return 0.0 if f < 0.0
    return 255.0 if f > 255.0
    f
  end
end

class Tone
  attr_reader :red, :green, :blue, :gray

  def initialize(red = 0.0, green = 0.0, blue = 0.0, gray = 0.0)
    set(red, green, blue, gray)
  end

  def set(red, green = nil, blue = nil, gray = 0.0)
    if red.is_a?(Tone)
      @red   = red.red
      @green = red.green
      @blue  = red.blue
      @gray  = red.gray
    else
      self.red   = red
      self.green = green
      self.blue  = blue
      self.gray  = gray
    end
    self
  end

  def red=(v);   @red   = clamp_signed(v); end
  def green=(v); @green = clamp_signed(v); end
  def blue=(v);  @blue  = clamp_signed(v); end
  def gray=(v);  @gray  = clamp_gray(v);   end

  def ==(other)
    other.is_a?(Tone) && @red == other.red && @green == other.green && @blue == other.blue && @gray == other.gray
  end

  def _dump(_limit)
    [@red, @green, @blue, @gray].pack("E4")
  end

  def self._load(str)
    r, g, b, gr = str.unpack("E4")
    new(r, g, b, gr)
  end

  private

  def clamp_signed(v)
    f = v.to_f
    return -255.0 if f < -255.0
    return 255.0 if f > 255.0
    f
  end

  def clamp_gray(v)
    f = v.to_f
    return 0.0 if f < 0.0
    return 255.0 if f > 255.0
    f
  end
end

class Rect
  attr_accessor :x, :y, :width, :height

  def initialize(x = 0, y = 0, width = 0, height = 0)
    set(x, y, width, height)
  end

  def set(x, y = nil, width = nil, height = nil)
    if x.is_a?(Rect)
      @x = x.x
      @y = x.y
      @width = x.width
      @height = x.height
    else
      @x = x.to_i
      @y = y.to_i
      @width = width.to_i
      @height = height.to_i
    end
    self
  end

  def empty
    @x = @y = @width = @height = 0
    self
  end

  def ==(other)
    other.is_a?(Rect) && @x == other.x && @y == other.y && @width == other.width && @height == other.height
  end
end
