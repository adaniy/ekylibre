# frozen_string_literal: true

module Accountancy
  module ConditionBuilder
    class JournalEntryConditionBuilder < Base
      # Build a condition for filter journal entries on period
      def period_condition(period, started_on:, stopped_on:, table_name:)
        if period.to_s == 'all'
          connection.quoted_true
        else
          conditions = []
          started_on, stopped_on = period.to_s.split('_')[0..1] unless period.to_s == 'interval'
          if started_on.present? && (started_on.is_a?(Date) || started_on =~ /^\d\d\d\d\-\d\d\-\d\d$/)
            conditions << "#{table_name}.printed_on >= #{quote(started_on.to_date)}"
          end
          if stopped_on.present? && (stopped_on.is_a?(Date) || stopped_on =~ /^\d\d\d\d\-\d\d\-\d\d$/)
            conditions << "#{table_name}.printed_on <= #{quote(stopped_on.to_date)}"
          end

          if conditions.empty?
            connection.quoted_false
          else
            '(' + conditions.join(' AND ') + ')'
          end
        end
      end

      # Build an SQL condition based on options which should contains acceptable states
      def journal_condition(journal_ids, table_name:)
        if journal_ids.blank?
          connection.quoted_false
        else
          "#{table_name}.journal_id IN (#{journal_ids.map { |journal_id| quote(journal_id.to_i) }.join(',')})"
        end
      end

      # Build an SQL condition based on options which should contains acceptable states
      # @param [Array<String, Symbol>] states
      # @param [String] table_name
      def state_condition(states, table_name:)
        if states.blank?
          JournalEntry.connection.quoted_false
        else
          "#{table_name}.state IN (#{states.map { |state| quote(state) }.join(',')})"
        end
      end
    end
  end
end
