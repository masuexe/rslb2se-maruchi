# frozen_string_literal: false

#==============================================================================
# Ruby 1.8.1 (RGSS2) -> Ruby 3.x Compatibility Layer
#==============================================================================

Fixnum = Integer unless defined?(Fixnum)
Bignum = Integer unless defined?(Bignum)
TRUE   = true    unless defined?(TRUE)
FALSE  = false   unless defined?(FALSE)
NIL    = nil     unless defined?(NIL)

class File
  class << self
    alias_method :exists?, :exist? unless method_defined?(:exists?)
  end
end

class Dir
  class << self
    alias_method :exists?, :exist? unless method_defined?(:exists?)
  end
end

class Array
  unless method_defined?(:nitems)
    def nitems
      compact.size
    end
  end
end

class Hash
  unless method_defined?(:index)
    alias_method :index, :key
  end
end

class String
  unless method_defined?(:each)
    alias_method :each, :each_line
  end
end

# RGSS2 Marshal streams contain UTF-8 strings without encoding IVARs (loaded as ASCII-8BIT in Ruby 3).
# Recursively normalize ASCII-8BIT strings that are valid UTF-8 so Chinese/Japanese script/data strings work seamlessly.
module MaruchiEncodingHelper
  def self.fix_strings!(obj, seen = {})
    oid = obj.object_id
    return obj if seen[oid]
    seen[oid] = true

    case obj
    when String
      if obj.encoding == Encoding::ASCII_8BIT
        dup_utf8 = obj.dup.force_encoding(Encoding::UTF_8)
        obj.force_encoding(Encoding::UTF_8) if dup_utf8.valid_encoding?
      end
    when Array
      obj.each { |el| fix_strings!(el, seen) }
    when Hash
      obj.each do |k, v|
        fix_strings!(k, seen)
        fix_strings!(v, seen)
      end
    else
      if obj.respond_to?(:instance_variables)
        obj.instance_variables.each do |iv|
          fix_strings!(obj.instance_variable_get(iv), seen)
        end
      end
    end
    obj
  end
end
