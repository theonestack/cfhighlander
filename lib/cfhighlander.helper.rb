module Cfhighlander


  module Helper


    def self.parameter_cfndsl_value(value)

      if value.class == String
        return "'#{value}'"
      end

      if value.class == Hash
        return value.to_json
      end

      return "'#{value}'"

    end

  end

end