# frozen_string_literal: true

module NamingFormats
  module LandParcels
    class BuildExampleInteractor
      def self.call(params)
        interactor = new(params)
        interactor.run
        interactor
      end

      attr_reader :example, :field_values, :error

      def initialize(params)
        @field_values = params[:fields_values]
      end

      def run
        @example = NamingFormats::LandParcels::BuildNamingService
                   .new(cultivable_zone: CultivableZone.first,
                        activity: Activity.first,
                        campaign: Campaign.first,
                        season: ActivitySeason.first,
                        free_field: "[#{I18n.t('free_field', scope: 'enumerize.naming_format_field_land_parcel.field_name', locale: Preference[:language])}]")
                   .perform(field_values: @field_values)
      rescue StandardError => exception
        fail!(exception.message)
      end

      def success?
        @error.nil?
      end

      def fail?
        !@error.nil?
      end

      private

        def fail!(error)
          @error = error
        end
    end
  end
end
