require_relative './cfhighlander.dsl.template'
require_relative './cfhighlander.factory.templatefinder'
require_relative './cfhighlander.model.component'
require 'fileutils'
require 'git'


module Cfhighlander

  module Factory

    class ComponentFactory

      attr_accessor :component_sources

      def initialize(component_sources = [])
        @template_finder = Cfhighlander::Factory::TemplateFinder.new(component_sources)
        @component_sources = component_sources
      end

      # Find component and given list of sources
      # @return [Cfhighlander::Factory::Component]
      def loadComponentFromTemplate(template_name, template_version = nil, component_name = nil)

        template_meta = @template_finder.findTemplate(template_name, template_version)

        raise StandardError, "highlander template #{template_name}@#{template_version} not located" +
            " in sources #{@component_sources}" if template_meta.nil?

        component_name = template_name if component_name.nil?
        return buildComponentFromLocation(template_meta, component_name)

      end


      def buildComponentFromLocation(template_meta, component_name)
        component = Model::Component.new(template_meta,
            component_name,
            self)
        component.factory = self
        component.load_config
        return component
      end

    end
  end

end
