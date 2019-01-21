$:.unshift File.dirname(__FILE__)
require 'generator_mixin'

module Graphiti
  class ResourceGenerator < ::Rails::Generators::NamedBase
    include GeneratorMixin

    source_root File.expand_path('../templates', __FILE__)

    argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

    class_option :'omit-comments',
      type: :boolean,
      default: false,
      aliases: ['--omit-comments', '-c'],
      desc: 'Generate without documentation comments'

    class_option :'actions',
      type: :array,
      default: nil,
      aliases: ['--actions', '-a'],
      desc: 'Array of controller actions to support, e.g. "index show destroy"'

    class_option :'default-attributes-class',
      banner: 'Model',
      type: :string,
      default: nil,
      desc: 'Specify to use attributes from a particular model'

    desc "This generator creates a resource file at app/resources, as well as corresponding controller/specs/route/etc"
    def generate_all
      generate_model
      generate_controller
      generate_application_resource unless application_resource_defined?
      generate_route
      generate_resource
      generate_resource_specs
      generate_api_specs
    end

    private

    class ModelAction
      attr_reader :class_name
      def initialize(class_name)
        @class_name = class_name
      end

      def invoke!
        unless class_name.safe_constantize
          raise "You must define a #{class_name} model before generating the corresponding resource."
        end
      end

      def revoke!
        # Do nothing on destroy
      end
    end

    def generate_model
      action(ModelAction.new(class_name))
    end

    def omit_comments?
      @options['omit-comments']
    end

    def default_attributes_class
      @default_attributes_class ||=
        if @options['default-attributes-class'].kind_of?(String)
          klass = @options['default-attributes-class'].classify
          begin
            klass.constantize
          rescue NameError
            raise NameError, "default-attributes-model #{klass} does not exist."
          end
        end
    end

    def default_attributes
      unless default_attributes_class.kind_of?(Class) && default_attributes_class <= ApplicationRecord
        raise "Unable to set #{self} default_attributes from #{default_attributes_class}. #{default_attributes_class} must be a kind of ApplicationRecord"
      end
      if default_attributes_class.table_exists?
        default_attributes_class.columns.map do |c|
          OpenStruct.new({ name: c.name.to_sym, type: c.type })
        end
      else
        raise "#{default_attributes_class} table must exist. Please run migrations."
      end
    end

    def responders?
      defined?(Responders)
    end

    def generate_controller
      to = File.join('app/controllers', class_path, "#{file_name.pluralize}_controller.rb")
      template('controller.rb.erb', to)
    end

    def generate_application_resource
      to = File.join('app/resources', class_path, "application_resource.rb")
      template('application_resource.rb.erb', to)
      require "#{::Rails.root}/#{to}"
    end

    def application_resource_defined?
      'ApplicationResource'.safe_constantize.present?
    end

    def generate_route
      # Rails 5.2 adds `plural_route_name`, fallback to `plural_table_name`
      plural_name = self.try(:plural_route_name) || plural_table_name

      code = "resources :#{plural_name}"
      code << %{, only: [#{actions.map { |a| ":#{a}" }.join(', ')}]} if actions.length < 5
      code << "\n"
      inject_into_file 'config/routes.rb', after: /ApplicationResource.*$\n/ do
        indent(code, 4)
      end
    end

    def generate_resource_specs
      opts = {}
      opts[:actions] = @options[:actions] if @options[:actions]
      invoke 'graphiti:resource_test', [resource_klass], opts
    end

    def generate_api_specs
      opts = {}
      opts[:actions] = @options[:actions] if @options[:actions]
      invoke 'graphiti:api_test', [resource_klass], opts
    end

    def generate_resource
      to = File.join('app/resources', class_path, "#{file_name}_resource.rb")
      template('resource.rb.erb', to)
      require "#{::Rails.root}/#{to}" if create?
    end

    def create?
      behavior == :invoke
    end

    def model_klass
      class_name.safe_constantize
    end

    def resource_klass
      "#{model_klass}Resource"
    end

    def type
      model_klass.name.underscore.pluralize
    end
  end
end
