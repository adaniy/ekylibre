# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2016 Brice Texier, David Joulin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

module Backend
  class TaxDeclarationsController < Backend::BaseController
    manage_restfully except: %i[new show index]

    unroll

    def self.tax_declarations_conditions
      code = search_conditions(tax_declarations: %i[reference_number number description]) + " ||= []\n"
      code << "if params[:period].present? && params[:period].to_s != 'all'\n"
      code << "  c[0] << ' AND #{TaxDeclaration.table_name}.started_on BETWEEN ? AND ?'\n"
      code << "  if params[:period].to_s == 'interval'\n"
      code << "    c << params[:started_on]\n"
      code << "    c << params[:stopped_on]\n"
      code << "  else\n"
      code << "    interval = params[:period].to_s.split('_')\n"
      code << "    c << interval.first\n"
      code << "    c << interval.second\n"
      code << "  end\n"
      code << "end\n"
      code << "unless params[:state].blank?\n"
      code << "  c[0] << ' AND #{TaxDeclaration.table_name}.state IN (?)'\n"
      code << "  c << params[:state]\n"
      code << "end\n"
      code << "c\n"
      code.c
    end

    list(conditions: tax_declarations_conditions, line_class: :status, order: { created_at: :desc, number: :desc }) do |t|
      t.action :edit, if: :editable?
      t.action :destroy, if: :destroyable?
      t.column :number, url: true
      t.column :responsible
      t.column :created_at
      t.column :started_on
      t.column :stopped_on
      t.column :deductible_tax_amount_balance, hidden: true
      t.column :collected_tax_amount_balance, hidden: true
      t.column :global_balance
      t.column :description, hidden: true
      t.status
      t.column :state_label, hidden: true
    end

    def index
      set_period_params

      notify_warning_now :tax_declaration_warning

      dataset_params = { period: params[:period], started_on: params[:started_on], stopped_on: params[:stopped_on], state: params[:state] }

      respond_to do |format|
        format.html do
          no_financial_year_opened = FinancialYear.opened.empty?
          financial_years_without_tax_declaration = FinancialYear.with_tax_declaration.empty?
          all_vat_declarations_fulfilled = FinancialYear.with_tax_declaration.all? &:fulfilled_tax_declaration?
          @display_alert = no_financial_year_opened || financial_years_without_tax_declaration || all_vat_declarations_fulfilled
        end

        format.pdf do
          return unless template = find_and_check(:document_template, params[:template])

          PrinterJob.perform_later('Printers::VatRegisterPrinter', template: template, perform_as: current_user, **dataset_params)
          notify_success(:document_in_preparation)
          redirect_back(fallback_location: root_path)
        end

        format.csv do
          return unless template = DocumentTemplate.find_by_nature(:vat_register)

          printer = Printers::VatRegisterPrinter.new(template: template, **dataset_params)
          csv_string = CSV.generate(headers: true) do |csv|
            printer.run_csv(csv)
          end
          send_data csv_string, filename: "#{printer.document_name}.csv"
        end
      end
    end

    # Displays details of one tax declaration selected with +params[:id]+
    def show
      return unless @tax_declaration = find_and_check

      respond_to do |format|
        format.html do
          t3e @tax_declaration.attributes
        end
        format.pdf do
          return unless template = find_and_check(:document_template, params[:template])

          PrinterJob.perform_later('Printers::PendingVatRegisterPrinter', template: template, tax_declaration: @tax_declaration, perform_as: current_user)
          notify_success(:document_in_preparation)
          redirect_back(fallback_location: { action: :index })
        end
        format.csv do
          return unless template = DocumentTemplate.find_by_nature(:pending_vat_register)

          printer = Printers::PendingVatRegisterPrinter.new(template: template, tax_declaration: @tax_declaration)
          csv_string = CSV.generate(headers: true) do |csv|
            printer.run_csv(csv)
          end
          send_data csv_string, filename: "#{printer.document_name}.csv"
        end
      end
    end

    def new
      financial_year = FinancialYear.find(params[:financial_year_id])
      tax_start = financial_year.next_tax_declaration_on
      if tax_start
        tax_stop = financial_year.tax_declaration_stopped_on(tax_start)
        tax_stop = financial_year.stopped_on if tax_stop > financial_year.stopped_on
      end
      sales_order = Sale.order_between(tax_start, tax_stop)

      if financial_year.tax_declaration_mode_none?
        redirect_to params[:redirect] || { action: :index }
      elsif !financial_year.previous_consecutives?
        notify_error :financial_years_missing
        redirect_to params[:redirect] || { action: :index }
      elsif sales_order.any?
        notify_sales_order(sales_order)
        redirect_to params[:redirect] || { action: :index }
      elsif financial_year.missing_tax_declaration?
        TaxDeclarationJob.perform_later(financial_year, current_user)
        notify_success(:vat_declaration_in_preparation)
        redirect_back(fallback_location: root_path)
      else
        notify_error :all_tax_declarations_have_already_existing
        redirect_to params[:redirect] || { action: :index }
      end
    end

    def propose
      return unless @tax_declaration = find_and_check

      @tax_declaration.propose
      redirect_to action: :show, id: @tax_declaration.id
    end

    def confirm
      return unless @tax_declaration = find_and_check

      @tax_declaration.confirm
      redirect_to action: :show, id: @tax_declaration.id
    end

    private

      def notify_sales_order(sales_order)
        sales = sales_order.map{|sale_order| helpers.link_to("#{:sale.tl} : #{sale_order.number}", backend_sale_path(sale_order))}
        return if sales.empty?

        notify_error(:tax_declaration_sales_order.tl(x: as_list(sales)), html: true)
      end

      # @param [Array<String>] elements
      # @return [String] HTML representation of a list that contains all the elements in `elements`
      def as_list(elements)
        helpers.content_tag(:ul) do
          elements.map do |element|
            helpers.content_tag(:li, element)
          end.join.html_safe
        end
      end
  end
end
