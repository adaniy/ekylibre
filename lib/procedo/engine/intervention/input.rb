# require 'procedo/engine/intervention/product_parameter'

module Procedo
  module Engine
    class Intervention
      class Input < Procedo::Engine::Intervention::Quantified
        attr_reader :component_id, :schematic_id

        def initialize(intervention, id, attributes = {})
          super(intervention, id, attributes)
          @component_id = attributes[:component_id].to_i if attributes[:component]
          @schematic_id = attributes[:schematic_id].to_i if attributes[:component]
        end

        def to_hash
          hash = super
          hash[:component_id] = @component_id
          hash[:schematic_id] = @schematic_id
          hash
        end

        def schematic_source=(field)
          @schematic_id = field.product.variant.id
        end

        def schematic_id=(value)
          @schematic_id = value
        end

        def component_id=(value)
          @component_id = value
        end
      end
    end
  end
end
