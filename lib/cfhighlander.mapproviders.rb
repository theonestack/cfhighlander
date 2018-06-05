module Cfhighlander

  ### Map Providers provide predefined maps or list of maps
  ### Aside from predefined mappings from providers
  ### Maps can be defined on component level in component.maps.yml file
  module MapProviders

    class AccountId

      @@maps = nil

      def self.getMaps(config)
        return @@maps if not @@maps.nil?
        @@maps = {
        }
        return @@maps
      end

      def self.getMapName
        return 'AccountId'
      end

      ### no getMapName, implicitly resolves to MapProvider name
      def self.getDefaultKey
        return "Ref('AWS::AccountId')"
      end

    end
  end

end