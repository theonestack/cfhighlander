module Cfhighlander

  module Util

    class Debug

      @@debug_folder_exists = false

      def self.create_debug_folder
        if ((ENV.key? 'CFHIGHLANDER_DEBUG') and (ENV['CFHIGHLANDER_DEBUG'] == '1'))
          FileUtils.mkdir_p "#{ENV['CFHIGHLANDER_WORKDIR']}/out/debug/"
          @@debug_folder_exists = true
        end unless @@debug_folder_exists
      end

      def self.debug_dump_cfn(template, step_name)
        create_debug_folder
        if ((ENV.key? 'CFHIGHLANDER_DEBUG') and (ENV['CFHIGHLANDER_DEBUG'] == '1'))
          template.subcomponents.each do |sub_component|
            path = "#{ENV['CFHIGHLANDER_WORKDIR']}/out/debug/#{sub_component.cfn_name}_#{step_name}.yaml"
            File.write(path, sub_component.component_loaded.cfn_model_raw.to_yaml)
          end
        end
      end

      def self.debug_dump(model, dump_name)
        create_debug_folder
        if ((ENV.key? 'CFHIGHLANDER_DEBUG') and (ENV['CFHIGHLANDER_DEBUG'] == '1'))
          path = "#{ENV['CFHIGHLANDER_WORKDIR']}/out/debug/#{dump_name}.yaml"
          File.write(path, model.to_yaml)
        end
      end


    end
  end
end