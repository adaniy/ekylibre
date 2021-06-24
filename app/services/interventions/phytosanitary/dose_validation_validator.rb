# frozen_string_literal: true

module Interventions
  module Phytosanitary
    class DoseValidationValidator < ProductApplicationValidator
      attr_reader :targets_and_shape, :unit_converter

      # @param [Array<Models::TargetAndShape>] targets_and_shape
      # @param [ProductUnitConverter] unit_converter
      def initialize(targets_and_shape:, unit_converter:)
        @targets_and_shape = targets_and_shape
        @unit_converter = unit_converter
      end

      # @param [Array<Models::ProductWithUsage>] products_usages
      # @return [Models::ProductApplicationResult]
      def validate(products_usages)
        result = Models::ProductApplicationResult.new

        if targets_and_shape.empty? || shapes_area.to_f.zero? || products_usages.any? { |pu| pu.usage.nil? }
          products_usages.each { |pu| result.vote_unknown(pu.product) }
        else
          products_usages.each do |pu|
            result = result.merge(validate_dose(pu))
          end
        end

        result
      end

      # @param [Models::ProductWithUsage]
      # @return [Models::ProductApplicationResult]
      def validate_dose(product_usage)
        result = Models::ProductApplicationResult.new

        params = build_params(product_usage)

        if product_usage.measure.dimension != 'none' || params.fetch(:"net_#{params[:into].base_dimension.to_sym}", None()).is_some?
          params.delete(:into)
            .fmap { |into| unit_converter.convert(product_usage.measure, into: into, **params) }
            .cata(
              none: -> { result.vote_unknown(product_usage.product) },
              some: ->(converted_dose) {
                reference = product_usage.usage.max_dose_measure

                if converted_dose > reference
                  result.vote_forbidden(product_usage.product, :dose_bigger_than_max.tl, on: :quantity)
                end
              }
            )
        else
          result.vote_unknown(product_usage.product)
        end

        result
      end

      private

        # @param [Models::ProductWithUsage] product_usage
        def build_params(product_usage)
          zero_as_nil = ->(value) { value.zero? ? None() : value }

          {
            into: Maybe(Onoma::Unit.find(product_usage.usage.dose_unit)),
            area: Maybe(shapes_area.in(:hectare)).fmap(&zero_as_nil),
            net_mass: Maybe(product_usage.product.net_mass).fmap(&zero_as_nil),
            net_volume: Maybe(product_usage.product.net_volume).fmap(&zero_as_nil),
            spray_volume: Maybe(product_usage.spray_volume).fmap(&zero_as_nil).in(:liter_per_hectare)
          }
        end

        def targets_data
          targets_and_shape.map.with_index { |e, i| [i.to_s, { shape: e.shape }] }.to_h
        end

        # @return [Measure<area>]
        def shapes_area
          value = targets_and_shape.sum do |ts|
            if ts.shape.nil?
              0
            else
              ts.shape.area
            end
          end

          Measure.new(value, :square_meter)
        end
    end
  end
end
