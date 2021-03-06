module Coercible
  class Coercer

    # Coerce String values
    class String < Object
      extend Configurable

      primitive ::String

      config_keys [ :boolean_map ]

      TRUE_VALUES  = %w[ 1 on  t true  y yes ].freeze
      FALSE_VALUES = %w[ 0 off f false n no  ].freeze
      BOOLEAN_MAP  = ::Hash[ TRUE_VALUES.product([ true ]) + FALSE_VALUES.product([ false ]) ].freeze

      INTEGER_REGEXP    = /[-+]?(?:[0-9]\d*)/.freeze
      EXPONENT_REGEXP   = /(?:[eE][-+]?\d+)/.freeze
      FRACTIONAL_REGEXP = /(?:\.\d+)/.freeze

      COERCION_FAILURE = ::Object.new.freeze

      NUMERIC_REGEXP    = /\A(
        #{INTEGER_REGEXP}#{FRACTIONAL_REGEXP}?#{EXPONENT_REGEXP}? |
        #{FRACTIONAL_REGEXP}#{EXPONENT_REGEXP}?
      )\z/x.freeze

      # Return default configuration for string coercer type
      #
      # @return [Configuration]
      #
      # @api private
      def self.config
        super { |config| config.boolean_map = BOOLEAN_MAP }
      end

      # Return boolean map from the config
      #
      # @return [::Hash]
      #
      # @api private
      attr_reader :boolean_map

      # Initialize a new string coercer instance
      #
      # @param [Coercer]
      #
      # @param [Configuration]
      #
      # @return [undefined]
      #
      # @api private
      def initialize(coercer = Coercer.new, config = self.class.config)
        super(coercer)
        @boolean_map = config.boolean_map
      end

      # Coerce give value to a constant
      #
      # @example
      #   coercer[String].to_constant('String') # => String
      #
      # @param [String] value
      #
      # @return [Object]
      #
      # @api public
      def to_constant(value)
        names = value.split('::')
        names.shift if names.first.empty?
        names.inject(::Object) { |*args| constant_lookup(*args) }
      end

      # Coerce give value to a symbol
      #
      # @example
      #   coercer[String].to_symbol('string') # => :string
      #
      # @param [String] value
      #
      # @return [Symbol]
      #
      # @api public
      def to_symbol(value)
        value.to_sym
      end

      # Coerce given value to Time
      #
      # @example
      #   coercer[String].to_time(string)  # => Time object
      #
      # @param [String] value
      #
      # @return [Time]
      #
      # @api public
      def to_time(value)
        parse_value(::Time, value, __method__)
      end

      # Coerce given value to Date
      #
      # @example
      #   coercer[String].to_date(string)  # => Date object
      #
      # @param [String] value
      #
      # @return [Date]
      #
      # @api public
      def to_date(value)
        parse_value(::Date, value, __method__)
      end

      # Coerce given value to DateTime
      #
      # @example
      #   coercer[String].to_datetime(string)  # => DateTime object
      #
      # @param [String] value
      #
      # @return [DateTime]
      #
      # @api public
      def to_datetime(value)
        parse_value(::DateTime, value, __method__)
      end

      # Coerce value to TrueClass or FalseClass
      #
      # @example with "T"
      #   coercer[String].to_boolean('T')  # => true
      #
      # @example with "F"
      #   coercer[String].to_boolean('F')  # => false
      #
      # @param [#to_s]
      #
      # @return [Boolean]
      #
      # @api public
      def to_boolean(value)
        boolean_map.fetch(value.downcase) {
          raise_unsupported_coercion(value, __method__)
        }
      end

      # Coerce value to integer
      #
      # @example
      #   coercer[String].to_integer('1')  # => 1
      #
      # @param [Object] value
      #
      # @return [Integer]
      #
      # @api public
      def to_integer(value)
        i = value.to_i

        if i.to_s == value
          i
        else
          # coerce to a Float first to evaluate scientific notation (if any)
          # that may change the integer part, then convert to an integer
          to_float(value).to_i
        end
      rescue UnsupportedCoercion
        raise_unsupported_coercion(value, __method__)
      end

      # Coerce value to float
      #
      # @example
      #   coercer[String].to_float('1.2')  # => 1.2
      #
      # @param [Object] value
      #
      # @return [Float]
      #
      # @api public
      def to_float(value)
        raise_on_coercion_failure(value, __method__) do
          to_numeric(value, :to_f)
        end
      end

      # Coerce value to decimal
      #
      # @example
      #   coercer[String].to_decimal('1.2')  # => #<BigDecimal:b72157d4,'0.12E1',8(8)>
      #
      # @param [Object] value
      #
      # @return [BigDecimal]
      #
      # @api public
      def to_decimal(value)
        raise_on_coercion_failure(value, __method__) do
          to_numeric(value, :to_d)
        end
      end

      private

      # Lookup a constant within a module
      #
      # @param [Module] mod
      #
      # @param [String] name
      #
      # @return [Object]
      #
      # @api private
      def constant_lookup(mod, name)
        if mod.const_defined?(name, *EXTRA_CONST_ARGS)
          mod.const_get(name, *EXTRA_CONST_ARGS)
        else
          mod.const_missing(name)
        end
      end

      # Match numeric string
      #
      # @param [String] value
      #   value to typecast
      # @param [Symbol] method
      #   method to typecast with
      #
      # @return [Numeric]
      #   number if matched, value if no match
      #
      # @api private
      def to_numeric(value, method)
        if value =~ NUMERIC_REGEXP
          $1.public_send(method)
        else
          COERCION_FAILURE
        end
      end

      # Parse the value or return it as-is if it is invalid
      #
      # @param [#parse] parser
      #
      # @param [String] value
      #
      # @return [Time]
      #
      # @api private
      def parse_value(parser, value, method)
        parser.parse(value)
      rescue ArgumentError
        raise_unsupported_coercion(value, method)
      end

      # Call the given block and return resulting value unless it has failed
      #
      # @param [String] value
      #   value to typecast
      #
      # @param [Symbol] method
      #
      # @return [Object]
      #
      # @api private
      def raise_on_coercion_failure(value, method, &block)
        result = block.call
        if result == COERCION_FAILURE
          raise_unsupported_coercion(value, method)
        else
          result
        end
      end

    end # class String

  end # class Coercer
end # module Coercible
