require_relative './highlander.dsl'
require_relative './highlander.factory.templatefinder'
require_relative './highlander.model.component'
require 'fileutils'
require 'git'


module Highlander

  module Factory

    class ComponentFactory

      attr_accessor :component_sources

      def initialize(component_sources = [])
        @template_finder = Highlander::Factory::TemplateFinder.new(component_sources)
      end

      # Find component and given list of sources
      # @return [Highlander::Factory::Component]
      def loadComponentFromTemplate(template_name, template_version = nil, component_name = nil)

        template_meta = @template_finder.findTemplate(template_name, template_version)

        raise StandardError, "highlander template #{template_name}@#{component_version_s} not located" +
            " in sources #{@component_sources}" if template_meta.nil?

        return buildComponentFromLocation(template_meta, component_name)

      end


      def buildComponentFromLocation(template_meta, component_name)
        component = Model::Component.new(template_meta, component_name)
        component.load_config
        return component
      end

    end
  end

end
