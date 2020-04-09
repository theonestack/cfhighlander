module Cfhighlander


  module Helper


    def self.parameter_cfndsl_value(value, nested = false)

      if value.class == String
        return "'#{value}'"
      end

      if value.class == Hash
        return value if nested
        return value.to_json
      end

      if value.class == Array
        return value.collect { |it| self.parameter_cfndsl_value(it, nested = true) }
      end

      return "'#{value}'"

    end

  end

end