module Highlander

  module Model

    class TemplateMetadata

      @template_name
      @template_version
      @template_location

      attr_reader :template_location,
          :template_version,
          :template_name

      def initialize(template_name:, template_version:, template_location:)
        @template_name = template_name
        @template_version = template_version
        @template_location = template_location
      end

    end

  end

end