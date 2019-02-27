require_relative '../hl_ext/common_helper'

module Cfhighlander

  module Config

    class Loader
      # creates top-level component configuration
      # for component.subcomponent.subsubcomponent.....config.yaml
      # configuration file
      # method allows for N-level configuration (no limitation on level)
      #  parameters
      #     component_location: component in hierarchy e.g. app.db.rds
      #     config: actual component configuration
      def get_nested_config(component_location, config)
        parts = component_location.split('.')
        i = 0
        current_config = Hash.new
        rval = current_config
        while i < parts.size
          current_config['components'] = Hash.new
          component_name = parts[i]
          current_config['components'][component_name] = { 'config' => Hash.new }
          current_config = current_config['components'][component_name]['config']
          i = i+1
        end
        current_config.extend config
        return rval
      end

    end

  end
end
