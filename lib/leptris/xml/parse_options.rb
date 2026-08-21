# frozen_string_literal: true

class Taurus::XML::ParseOptions
  DEFAULT_XML = 0
  RECOVER = 1 << 0
  NOERROR = 1 << 5
  NOWARNING = 1 << 6
  NOCDATA = 1 << 8
  STRICT = 1 << 18

  attr_reader :options

  def initialize(options = DEFAULT_XML)
    @options = options.to_i
  end

  def strict?;    !@options.zero?; end
  def recover?;   @options & RECOVER != 0; end
end
