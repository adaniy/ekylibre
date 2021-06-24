# frozen_string_literal: true

class FinancialYearExchangeImport
  class InvalidFile < RuntimeError; end

  attr_reader :error

  def initialize(file, exchange)
    @file = file
    @exchange = exchange
  end

  def run
    ApplicationRecord.transaction do
      read_and_parse_file || rollback!
      ensure_headers_are_valid || rollback!
      ensure_all_journals_exists || rollback!
      ensure_entries_included_in_financial_year_date_range || rollback!
      # don t destroy entries in accountant journal anymore
      # destroy_previous_journal_entries
      import_journal_entries || rollback!
      save_file
    end
    @error.blank?
  end

  private

    attr_reader :file, :exchange, :parsed

    def read_and_parse_file
      @parsed = CSV.parse(file.read, headers: true, header_converters: ->(header) { format_header(header) })
      true
    rescue => error
      message = I18n.translate('activerecord.errors.models.financial_year_exchange.csv_file_invalid')
      @error = InvalidFile.new(message)
      @internal_error = error
      false
    end

    def ensure_headers_are_valid
      if exchange.format == 'isacompta'
        expected = %i[id jour numero_compte journal libelle_journal type_compte numero_piece libelle_ecriture debit credit lettrage date_echeance sequence_analytique]
      else
        expected = %i[jour numero_compte journal tiers numero_piece libelle_ecriture debit credit lettrage]
      end
      return true if parsed.headers.to_set == expected.to_set

      message = I18n.translate('activerecord.errors.models.financial_year_exchange.csv_file_headers_invalid')
      @error = InvalidFile.new(message)
      false
    end

    def ensure_all_journals_exists
      journal_codes = parsed.map { |row| row[:journal] }.uniq
      if exchange.format == 'isacompta'
        existing_journal_codes = Journal.where(isacompta_code: journal_codes).pluck(:isacompta_code)
      else
        existing_journal_codes = Journal.where(code: journal_codes).pluck(:code)
      end

      return true if existing_journal_codes.length == journal_codes.length

      message = I18n.translate('activerecord.errors.models.financial_year_exchange.csv_file_journals_invalid', codes: (journal_codes - existing_journal_codes).join(', '))
      @error = InvalidFile.new(message)
      false
    end

    def ensure_entries_included_in_financial_year_date_range
      range = (exchange.financial_year.started_on..exchange.financial_year.stopped_on)
      return true if parsed.all? do |row|
        row_date = begin
                     if exchange.format == 'isacompta'
                       Date.strptime(row[:jour], "%d%m%Y")
                     else
                       Date.parse(row[:jour])
                     end
                   rescue
                     nil
                   end
        row_date && range.cover?(row_date)
      end

      message = I18n.translate('activerecord.errors.models.financial_year_exchange.csv_file_entry_dates_invalid')
      @error = InvalidFile.new(message)
      false
    end

    # don t use this method for the moment
    def destroy_previous_journal_entries
      financial_year = exchange.financial_year
      accountant = financial_year.accountant
      accountant.booked_journals.each do |journal|
        journal.entries.where(printed_on: financial_year.started_on..financial_year.stopped_on).find_each do |entry|
          entry.mark_for_exchange_import!
          entry.destroy
        end
      end
      true
    end

    def import_journal_entries
      import_journal_entries!
      true
    rescue => e
      @error = e
      false
    end

    def import_journal_entries!
      parsed.group_by { |row| row[:numero_piece] }.each do |entry_number, rows|
        sample_row = rows.first
        journal_code = sample_row[:journal]
        printed_on = sample_row[:jour]
        journal = Journal.find_by(accountant_id: exchange.financial_year.accountant_id, code: journal_code)
        # in case of isacompta code journal in CSV and date format 'JJMMAAAA'
        if exchange.format == 'isacompta'
          journal ||= Journal.find_by(accountant_id: exchange.financial_year.accountant_id, isacompta_code: journal_code)
          printed_on = Date.strptime(printed_on, "%d%m%Y")
        end
        # we take only entry link to accountant journal
        next unless journal

        items = rows.each_with_object([]) do |row, array|
          if exchange.format == 'isacompta'
            array << {
              name: row[:libelle_ecriture],
              real_debit: row[:debit],
              real_credit: row[:credit],
              isacompta_letter: row[:lettrage],
              account: Account.find_by(number: row[:numero_compte])
            }
          else
            array << {
              name: row[:libelle_ecriture],
              real_debit: row[:debit],
              real_credit: row[:credit],
              letter: row[:lettrage],
              account: Account.find_by(number: row[:numero_compte])
            }
          end
        end
        entry = journal.entries.build(number: entry_number, printed_on: printed_on)
        entry.mark_for_exchange_import!
        entry.items_attributes = items
        save_entry! entry
      end
    end

    def save_entry!(entry)
      return true if entry.save

      message = I18n.translate('activerecord.errors.models.financial_year_exchange.csv_file_entry_invalid', entry_number: entry.number)
      @error = InvalidFile.new(message)
      @internal_error = ActiveRecord::RecordInvalid.new(entry)
      raise error
    end

    def save_file
      exchange.import_file = file
      @error = ActiveRecord::RecordInvalid.new(exchange) unless exchange.save
    end

    def format_header(header)
      I18n.transliterate(header.force_encoding('UTF-8')).underscore.gsub(/\s/, '_').to_sym
    end

    def rollback!
      raise ActiveRecord::Rollback
    end
end
