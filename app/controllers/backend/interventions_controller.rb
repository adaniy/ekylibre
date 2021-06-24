# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2013 Brice Texier
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

require_dependency 'procedo'

using Ekylibre::Utils::DateSoftParse

module Backend
  class InterventionsController < Backend::BaseController
    manage_restfully t3e: { procedure_name: '(RECORD.procedure ? RECORD.procedure.human_name : nil)'.c },
                     continue: %i[nature procedure_name crop_group_ids]

    respond_to :pdf, :odt, :docx, :xml, :json, :html, :csv

    unroll

    # params:
    #   :q Text search
    #   :cultivable_zone_id
    #   :campaign_id
    #   :product_nature_id
    #   :support_id
    def self.list_conditions
      conn = Intervention.connection
      # , productions: [:name], campaigns: [:name], activities: [:name], products: [:name]
      expressions = []
      expressions << 'CASE ' + Procedo.selection.map { |l, n| "WHEN #{Intervention.table_name}.procedure_name = #{conn.quote(n)} THEN #{conn.quote(l)}" }.join(' ') + " ELSE '' END"

      code = <<~RUBY
        #{search_conditions({ interventions: %i[state procedure_name number] }, expressions: expressions)} ||= []

        if params[:state].present?
          c[0] << ' AND #{Intervention.table_name}.state IN (?)'
          c << params[:state]
        end

        if params[:nature].present?
          c[0] << ' AND #{Intervention.table_name}.nature IN (?)'
          c << params[:nature]
        end

        c[0] << ' AND #{Intervention.table_name}.state != ?'
        c[0] << ' AND ((#{Intervention.table_name}.nature = ? AND I.request_intervention_id IS NULL) OR #{Intervention.table_name}.nature = ?)'
        c << '#{Intervention.state.rejected}'
        c << 'request'
        c << 'record'

        if params[:cultivable_zone_id].present?
          c[0] << ' AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM activity_productions_interventions INNER JOIN #{ActivityProduction.table_name} ON #{ActivityProduction.table_name}.id = activity_production_id INNER JOIN #{CultivableZone.table_name} ON #{CultivableZone.table_name}.id = #{ActivityProduction.table_name}.cultivable_zone_id WHERE #{CultivableZone.table_name}.id = ' + params[:cultivable_zone_id] + ')'
          c
        end

        if params[:procedure_name_id].present?
          c[0] << ' AND #{Intervention.table_name}.procedure_name IN (?)'
          c << params[:procedure_name_id]
        end

        if params[:activity_id].present?
          c[0] << 'AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM interventions INNER JOIN activities_interventions ON activities_interventions.intervention_id = interventions.id INNER JOIN activities ON activities.id = activities_interventions.activity_id WHERE activities.id = ?)'
          c << params[:activity_id].to_i
        end

        if params[:target_id].present?
          c[0] << ' AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM intervention_parameters WHERE product_id IN (?))'
          c << params[:target_id].to_i
        end

        if params[:label_id].present?
          c[0] << ' AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM intervention_labellings WHERE label_id IN (?))'
          c << params[:label_id].to_i
        end

        if params[:worker_id].present?
           c[0] << ' AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM interventions INNER JOIN #{InterventionDoer.table_name} ON #{InterventionDoer.table_name}.intervention_id = #{Intervention.table_name}.id WHERE #{InterventionDoer.table_name}.product_id = ?)'
           c << params[:worker_id].to_i
        end

        if params[:equipment_id].present?
           c[0] << ' AND #{Intervention.table_name}.id IN (SELECT intervention_id FROM interventions INNER JOIN #{InterventionParameter.table_name} ON #{InterventionParameter.table_name}.intervention_id = #{Intervention.table_name}.id WHERE #{InterventionParameter.table_name}.product_id = ?)'
           c << params[:equipment_id].to_i
        end

        if current_period_interval.present? && current_period.present?
          if current_period_interval.to_sym == :day
            c[0] << ' AND EXTRACT(DAY FROM #{Intervention.table_name}.started_at) = ? AND EXTRACT(MONTH FROM #{Intervention.table_name}.started_at) = ? AND EXTRACT(YEAR FROM #{Intervention.table_name}.started_at) = ?'
            c << current_period.to_date.day
            c << current_period.to_date.month
            c << current_period.to_date.year

          elsif current_period_interval.to_sym == :week
            c[0] << ' AND #{Intervention.table_name}.started_at >= ? AND #{Intervention.table_name}.stopped_at <= ?'
            c << current_period.to_date.at_beginning_of_week.to_time.beginning_of_day
            c << current_period.to_date.at_end_of_week.to_time.end_of_day

          elsif current_period_interval.to_sym == :month
            c[0] << ' AND EXTRACT(MONTH FROM #{Intervention.table_name}.started_at) = ? AND EXTRACT(YEAR FROM #{Intervention.table_name}.started_at) = ?'
            c << current_period.to_date.month
            c << current_period.to_date.year

          elsif current_period_interval.to_sym == :year
            c[0] << ' AND EXTRACT(YEAR FROM #{Intervention.table_name}.started_at) = ?'
            c << current_period.to_date.year
          end
        end

        c
      RUBY

      code.c
    end

    # INDEX
    # @TODO conditions: list_conditions, joins: [:production, :activity, :campaign, :support]
    # conditions: list_conditions,
    list(conditions: list_conditions, order: { started_at: :desc }, line_class: :status, includes: [:receptions, :activities, :targets, :participations], joins: 'LEFT OUTER JOIN interventions I ON interventions.id = I.request_intervention_id') do |t|
      t.action :sell, on: :both, method: :post
      t.action :edit, if: :updateable?
      t.action :destroy, if: :destroyable?, unless: :receptions_is_given?
      t.column :name, sort: :procedure_name, url: true
      t.column :procedure_name, hidden: true
      # t.column :production, url: true, hidden: true
      # t.column :campaign, url: true
      t.column :human_activities_names
      t.column :started_at
      t.column :stopped_at, hidden: true
      t.column :human_working_duration, on_select: :sum, value_method: 'working_duration.in(:second).in(:hour)', datatype: :decimal
      t.status
      t.column :state_label, hidden: true
      t.column :human_target_names
      t.column :human_working_zone_area, on_select: :sum, datatype: :decimal
      t.column :total_cost, label_method: 'costing&.decorate&.human_total_cost', currency: true, datatype: :decimal
      t.column :nature
      t.column :issue, url: true
      t.column :trouble_encountered, hidden: true
      # t.column :casting
      # t.column :human_target_names, hidden: true
    end

    # SHOW

    list(:product_parameters, model: :intervention_product_parameters, conditions: { intervention_id: 'params[:id]'.c }, order: { created_at: :desc }) do |t|
      t.column :name, sort: :reference_name
      t.column :product, url: true
      # t.column :human_roles, sort: :roles, label: :roles
      t.column :quantity_population
      t.column :unit_name, through: :variant
      # t.column :working_zone, hidden: true
      t.column :variant, url: { controller: 'RECORD.variant.class.name.tableize'.c, namespace: :backend }
    end

    list(
      :service_deliveries,
      model: :reception_items,
      conditions: { id: 'ReceptionItem.joins(:reception).where(parcels: { intervention_id: params[:id]}).pluck(:id)'.c }
    ) do |t|
      t.column :variant, url: { controller: 'RECORD.variant.class.name.tableize'.c, namespace: :backend }, label: :service
      t.column :quantity
      t.column :sender_full_name, label: :provider, through: :reception, url: { controller: 'backend/entities', id: 'RECORD.reception.sender.id'.c }
      t.column :purchase_order_number, label: :purchase_order, through: :reception, url: { controller: 'backend/purchase_orders', id: 'RECORD.reception.purchase_order.id'.c }
      t.column :reception, url: true
      t.column :unit_pretax_amount, currency: true
      t.column :pretax_amount, currency: true
    end

    list(:record_interventions, model: :interventions, conditions: { request_intervention_id: 'params[:id]'.c }, order: 'interventions.started_at DESC') do |t|
      # t.column :roles, hidden: true
      t.column :name, sort: :reference_name
      t.column :started_at, datatype: :datetime
      t.column :stopped_at, datatype: :datetime
      t.column :human_activities_names, through: :intervention
      t.column :human_working_duration, through: :intervention
      t.column :human_working_zone_area, through: :intervention
    end

    # Show one intervention with params_id
    def show
      return unless @intervention = find_and_check

      t3e @intervention, procedure_name: @intervention.procedure.human_name, nature: @intervention.request? ? :planning_of.tl : nil
      respond_to do |format|
        format.html
        format.pdf {
          return unless (template = find_and_check :document_template, params[:template])

          PrinterJob.perform_later('Printers::InterventionSheetPrinter', id: params[:id], template: template, perform_as: current_user)
          notify_success(:document_in_preparation)
          redirect_to backend_interventions_path
        }
      end

    end

    # TODO: Reimplement this with correct use of permitted params
    def new
      # The use of unsafe_params is a crutch to have this code working fast.
      # However, this whole method should be implemented using REAL permitted_params.
      unsafe_params = params.to_unsafe_h

      options = {}
      %i[actions custom_fields description event_id issue_id
         nature number prescription_id procedure_name
         request_intervention_id started_at state
         stopped_at trouble_description trouble_encountered
         whole_duration working_duration].each do |param|
        options[param] = unsafe_params[param]
      end

      if params['targets_attributes'].present?
        id = params['targets_attributes'].first['product_id'].to_i
      end

      # check if a target product exist when selecting a procedure otherwise send a flash message
      if params['procedure_name'].present?
        procedure = Procedo::Procedure.find(params['procedure_name'])
        target_parameter = procedure.parameters_of_type(:target, true).first if procedure

        # if theres no products relatives to selected procedure (target && filter), notify user and clean params
        if procedure.present? && target_parameter.present?
          if target_parameter.is_a?(Procedo::Procedure::ProductParameter)
            filter = target_parameter.filter
          else
            notify_warning_now(:no_target_exist_on_procedure)
          end
          if Product.of_expression(filter).blank?
            # notify user and remove unsafe_params concerning targets_attributes && group_parameters_attributes
            notify_warning_now(:no_product_matching_current_filter)
            unsafe_params.delete('targets_attributes')
            unsafe_params.delete('group_parameters_attributes')
          end
        end
      end

      if params[:procedure_name].present? && params[:crop_group_ids].present?
        crop_group_params_computation = ::Interventions::CropGroupParamsComputation.new(params[:procedure_name], params[:crop_group_ids])
        options.merge!(crop_group_params_computation.options)
        options[:intervention_crop_groups_attributes] = params[:crop_group_ids].map{ |id| { crop_group_id: id } }
        if crop_group_params_computation.rejected_crops.any?
          notify_warning_now(:intervention_crops_rejected,
                             crops: helpers.as_unordered_list(crop_group_params_computation.rejected_crops.map(&:name)),
                             html: true)
        end
      end

      # , :doers, :inputs, :outputs, :tools
      %i[group_parameters targets].each do |param|
        next unless unsafe_params.include?(:intervention) || unsafe_params.include?("#{param}_attributes")

        options[:"#{param}_attributes"] = unsafe_params["#{param}_attributes"] || []
        next unless options[:targets_attributes]

        targets = if options[:targets_attributes].is_a? Array
                    options[:targets_attributes].collect { |k, _| k[:product_id] }
                  else
                    options[:targets_attributes].collect { |_, v| v[:product_id] }
                  end
        availables = Product.where(id: targets).at(Time.zone.now - 1.hour).collect(&:id)

        if availables.any? && filter.present? && Product.where(id: availables).of_expression(filter).blank?
          notify_warning_now(:no_availables_product_matching_current_filter)
        elsif availables.blank?
          notify_warning_now(:no_availables_product_on_current_campaign)
        end

        options[:targets_attributes].select! do |k, v|
          # This does not work with Rails 5 without the unsafe_params trick
          obj = k.is_a?(Hash) ? k : v
          obj.include?(:product_id) && availables.include?(obj[:product_id].to_i)
        end
      end

      %i[doers inputs outputs tools participations working_periods intervention_crop_groups].each do |param|
        next unless params.include? :intervention

        options[:"#{param}_attributes"] = permitted_params["#{param}_attributes"] || []
      end
      # consume preference and erase
      if params[:keeper_id] && (p = current_user.preferences.get(params[:keeper_id])) && p.value.present?

        options[:targets_attributes] = p.value.split(',').collect do |v|
          hash = {}

          hash[:product_id] = v if Product.find_by(id: v)

          if params[:reference_name]
            next unless params[:reference_name] == 'animal'

            hash[:reference_name] = params[:reference_name]
          end

          if params[:new_group] && (g = Product.find_by(id: params[:new_group]))
            hash[:new_group_id] = g.id
          end

          if params[:new_container] && (c = Product.find_by(id: params[:new_container]))
            hash[:new_container_id] = c.id
          end

          hash
        end.compact

        p.set! nil
      end

      if options[:warning]
        notify_warning_now(options[:warning], html: true)
      end

      @intervention = Intervention.new(options)

      from_request = Intervention.find_by(id: params[:request_intervention_id])
      @intervention = from_request.initialize_record if from_request

      render(locals: { cancel_url: { action: :index }, with_continue: true })
    end

    def create
      unless permitted_params[:participations_attributes].nil?
        participations = permitted_params[:participations_attributes]

        participations.each_pair do |key, value|
          participations[key] = JSON.parse(value)
        end

        permitted_params[:participations_attributes] = participations
      end

      # binding.pry
      @intervention = Intervention.new(permitted_params)
      url = if params[:create_and_continue]
              { action: :new, continue: true }
            elsif URI(request.referer).path == '/backend/schedulings/new_detailed_intervention'
              backend_schedulings_path
            else
              params[:redirect] || { action: :show, id: 'id'.c }
            end

      return if save_and_redirect(@intervention, url: url, notify: :record_x_created, identifier: :number)

      render(locals: { cancel_url: { action: :index }, with_continue: true })
    end

    def update
      @intervention = find_and_check

      unless permitted_params[:participations_attributes].nil?
        participations = permitted_params[:participations_attributes]
        participations.each_pair do |key, value|
          participations[key] = JSON.parse(value)
        end

        permitted_params[:participations_attributes] = participations

        delete_working_periods(participations)
      end
      if @intervention.update(permitted_params)
        redirect_to action: :show
      else
        render :edit
      end
    end

    def sell
      interventions = params[:id].split(',')
      return unless interventions

      if interventions
        redirect_to new_backend_sale_path(intervention_ids: interventions)
      else
        redirect_to action: :index
      end
    end

    def purchase
      interventions = params[:id].split(',')
      if interventions
        redirect_to new_backend_purchase_invoice_path(intervention_ids: interventions)
      else
        redirect_to action: :index
      end
    end

    # Computes impacts of a updated value in an intervention input context
    def compute
      unless params[:intervention]
        head(:unprocessable_entity)
        return
      end
      intervention_params = params[:intervention].deep_symbolize_keys
      procedure = Procedo.find(intervention_params[:procedure_name])
      unless procedure
        head(:not_found)
        return
      end

      unless intervention_params[:tools_attributes].nil?
        intervention_params[:tools_attributes]
          .values
          .each { |tool_attributes| tool_attributes.except!(:readings_attributes) }
      end

      intervention = Procedo::Engine.new_intervention(intervention_params)
      begin
        intervention.impact_with!(params[:updater])
        updater_id = 'intervention_' + params[:updater].gsub('[', '_attributes_').tr(']', '_')
        # raise intervention.to_hash.inspect
        respond_to do |format|
          # format.xml  { render xml: intervention.to_xml }
          format.json { render json: { updater_id: updater_id, intervention: intervention, handlers: intervention.handlers_states, procedure_states: intervention.procedure_states }.to_json }
        end
      rescue Procedo::Error => e
        respond_to do |format|
          # format.xml  { render xml:  { errors: e.message }, status: 500 }
          format.json { render json: { errors: e.message }, status: 500 }
        end
      end
    end

    def purchase_order_items
      purchase_order = Purchase.find(params[:purchase_order_id])
      reception = Intervention.find(params[:intervention_id]).receptions.first if params[:intervention_id].present?
      order_hash = if reception.present? && reception.purchase_id == purchase_order.id
                     find_items(reception.id, reception.pretax_amount, reception.items.of_role('service'))
                   else
                     find_items(purchase_order.id, purchase_order.pretax_amount, purchase_order.items.of_role('service'))
                   end
      respond_to do |format|
        format.json { render json: order_hash }
      end
    end

    def modal
      if params[:intervention_id]
        @intervention = Intervention.find(params[:intervention_id])
        render partial: 'backend/interventions/details_modal', locals: { intervention: @intervention }
      end

      if params[:interventions_ids]
        @interventions = Intervention.find(params[:interventions_ids].split(','))

        if params[:modal_type] == 'delete'
          render partial: 'backend/interventions/delete_modal', locals: { interventions: @interventions }
        else
          render partial: 'backend/interventions/change_state_modal', locals: { interventions: @interventions }
        end
      end
    end

    def change_state
      unless state_change_permitted_params
        head :unprocessable_entity
        return
      end

      interventions_ids = JSON.parse(state_change_permitted_params[:interventions_ids]).to_a
      new_state = state_change_permitted_params[:state].to_sym

      @interventions = Intervention.find(interventions_ids)

      Intervention.transaction do
        @interventions.each do |intervention|
          next if intervention.request? && intervention.record_interventions.any?

          if intervention.nature == :record && new_state == :rejected

            unless intervention.request_intervention_id.nil?
              intervention_request = Intervention.find(intervention.request_intervention_id)

              if state_change_permitted_params[:delete_option].to_sym == :delete_request
                intervention_request.destroy!
              else
                intervention_request.parameters = intervention.parameters
                intervention_request.save!
              end
            end

            intervention.destroy!
            next
          end

          if intervention.nature == :request && new_state == :rejected
            intervention.state = new_state

            next unless intervention.valid?

            intervention.save!

            next
          end

          new_intervention = intervention

          if intervention.nature == :request
            new_intervention = intervention.dup
            intervention.working_periods.each do |wp|
              new_intervention.working_periods.build(wp.dup.attributes)
            end
            intervention.group_parameters.each do |group_parameter|
              duplicate_group_parameter = group_parameter.dup
              duplicate_group_parameter.intervention = new_intervention
              %i[doers inputs outputs targets tools].each do |type|
                parameters = group_parameter.send(type)
                parameters.each do |parameter|
                  duplicate_parameter = parameter.dup
                  duplicate_parameter.group = duplicate_group_parameter
                  duplicate_parameter.intervention = new_intervention
                  duplicate_group_parameter.send(type) << duplicate_parameter
                end
              end
              new_intervention.group_parameters << duplicate_group_parameter
            end
            intervention.product_parameters.where(group_id: nil).each do |parameter|
              new_intervention.product_parameters << parameter.dup
            end
            intervention.participations.includes(:working_periods).each do |participation|
              dup_participation = participation.dup.attributes.merge({ state: 'in_progress' })
              new_participation = new_intervention.participations.build(dup_participation)
              participation.working_periods.each do |wp|
                new_participation.working_periods.build(wp.dup.attributes)
              end
            end
            intervention.receptions.each do |reception|
              new_intervention.receptions << reception
            end
            new_intervention.request_intervention_id = intervention.id
          end

          if new_state == :validated
            new_intervention.validator = current_user
          end

          new_intervention.state = new_state
          new_intervention.nature = :record

          next unless new_intervention.valid?

          new_intervention.save!
        end
      end

      if @interventions.count == 1 && !(params[:intervention][:redirect] == 'false')
        intervention = @interventions.first
        if intervention.request? && intervention.record_interventions.any?
          record_intervention = intervention.record_interventions.first
          return redirect_to backend_intervention_path(record_intervention)
        end
      end

      redirect_to_back
    end

    # FIXME: Not linked directly to interventions
    def change_page
      options = params.require(:interventions_taskboard).permit(:q, :state, :nature, :cultivable_zone_id, :procedure_name_id, :activity_id, :target_id, :worker_id, :equipment_id, :period_interval, :period, :page)
      options[:period_interval] ||= current_period_interval
      options[:period] ||= current_period

      @interventions_by_state = {
        requests: Intervention.with_unroll(options.merge(nature: :request)),
        current: Intervention.with_unroll(options.merge(nature: :record, state: :in_progress)),
        finished: Intervention.with_unroll(options.merge(nature: :record, state: :done)),
        validated: Intervention.with_unroll(options.merge(nature: :record, state: :validated))
      }
      respond_to do |format|
        format.js
      end
    end

    def generate_buttons
      get_interventions

      if interventions_validations
        render json: nil
      elsif params[:icon_btn] == 'true'
        render json: { translation: :duplicate_x_selected_interventions.tl(count: @interventions.count) }
      else
        render partial: 'generate_buttons'
      end
    end

    def duplicate_interventions
      get_interventions
      if interventions_validations
        render json: nil
      else
        render partial: 'duplicate_modal',
               locals: { intervention: @interventions.first }
      end
    end

    def create_duplicate_intervention
      find_intervention
      new_intervention
      if @new_intervention.save
        params[:interventions].delete(params[:intervention])
        duplicate_interventions
      else
        render json: { errors: @new_intervention.errors.full_messages.join(', ') }
      end
    end

    def compare_realised_with_planned
      @intervention = Intervention.find(params[:intervention_id])
      @request_intervention = @intervention.request_intervention
      respond_to do |format|
        format.js
      end
    end

    def validate_harvest_delay
      params_obj = FormObjects::Backend::Interventions::ValidateHarvestReentry.new(params.permit(:date, :date_end, :ignore_intervention, targets: []))
      return head :bad_request unless params_obj.valid?

      date = DateTime.soft_parse(params_obj.date)
      date_end = DateTime.soft_parse(params_obj.date_end) || date
      parcels = Product.find(params_obj.targets)
      ignore_intervention = params_obj.intervention

      harvest_advisor = ::Interventions::Phytosanitary::PhytoHarvestAdvisor.new

      result = parcels.map do |parcel|
        result = harvest_advisor.harvest_possible?(parcel, date, date_end: date_end, ignore_intervention: ignore_intervention)
        {
          id: parcel.id,
          possible: result.possible,
          date: result.possible ? nil : result.next_possible_date
        }
      end

      render json: { targets: result }
    end

    def validate_reentry_delay
      params_obj = FormObjects::Backend::Interventions::ValidateHarvestReentry.new(params.permit(:date, :date_end, :ignore_intervention, targets: []))
      return head :bad_request unless params_obj.valid?

      date = DateTime.soft_parse(params_obj.date)
      date_end = DateTime.soft_parse(params_obj.date_end) || date
      parcels = Product.find(params_obj.targets)
      ignore_intervention = params_obj.intervention

      harvest_advisor = ::Interventions::Phytosanitary::PhytoHarvestAdvisor.new
      result = Array(parcels).map do |parcel|
        advisor_result = harvest_advisor.reentry_possible?(parcel, date, date_end: date_end, ignore_intervention: ignore_intervention)

        data = { id: parcel.id, possible: advisor_result.possible, }
        unless advisor_result.possible
          data = {
            **data,
            period_duration: advisor_result.period_duration.iso8601,
            date: advisor_result.next_possible_date
          }
        end
        data
      end

      render json: { targets: result }
    end

    private

      def find_interventions
        intervention_ids = params[:id].split(',')
        interventions = intervention_ids.map { |id| Intervention.find_by(id: id) }.compact
        unless interventions.any?
          notify_error :no_interventions_given
          redirect_to(params[:redirect] || { action: :index })
          return nil
        end
        interventions
      end

      def delete_working_periods(form_participations)
        working_periods_ids = form_participations.values
                                                 .map { |participation| participation['working_periods_attributes'].map { |working_period| working_period['id'] } }
                                                 .flatten
                                                 .compact
                                                 .uniq
                                                 .map(&:to_i)

        intervention_participations_ids = form_participations.values
                                                             .map { |participation| participation[:id] }

        saved_working_periods_ids = @intervention
                                      .participations
                                      .where(id: intervention_participations_ids)
                                      .map { |participation| participation.working_periods.map(&:id) }
                                      .flatten

        working_periods_to_destroy = saved_working_periods_ids - working_periods_ids
        InterventionWorkingPeriod.where(id: working_periods_to_destroy).destroy_all

        @intervention.reload
      end

      def state_change_permitted_params
        params.require(:intervention).permit(:interventions_ids, :state, :delete_option)
      end

      def find_items(id, pretax_amount, items)
        order_hash = { id: id, pretax_amount: pretax_amount }
        items.each do |item|
          order_hash[:items] = [] if order_hash[:items].nil?
          order_hash[:items] << { id: item.id,
                                  variant_id: item.variant_id,
                                  name: item.variant.name,
                                  quantity: item.quantity,
                                  unit_pretax_amount: item.unit_pretax_amount,
                                  is_reception: item.class == ReceptionItem,
                                  purchase_order_item: item.try(:purchase_order_item_id) || item.id,
                                  pretax_amount: item.pretax_amount,
                                  role: item.role,
                                  current_stock: item.variant&.current_stock }
        end
        order_hash
      end

      def get_interventions
        @interventions = Intervention.where(id: params[:interventions])
      end

      def interventions_validations
        @interventions.empty? || @interventions.select { |i| i.nature == 'record' }.present?
      end

      def new_intervention
        new_date = params[:date].to_time if params[:date].present?
        attrs = Rack::Utils.parse_nested_query(params['form'])['intervention']

        @new_intervention = @intervention.dup
        @new_intervention.started_at = @new_intervention.started_at.change(year: new_date.year, month: new_date.month, day: new_date.day) if new_date
        @new_intervention.stopped_at = @new_intervention.started_at + @intervention.duration.seconds
        @new_intervention.parent_id = @intervention.id

        @intervention.working_periods.each do |working_period|
          duplicate_working_period = working_period.dup
          duplicate_working_period.intervention = @new_intervention
          duplicate_working_period.started_at = duplicate_working_period.started_at.change(year: new_date.year, month: new_date.month, day: new_date.day) if new_date
          duplicate_working_period.stopped_at = duplicate_working_period.started_at + duplicate_working_period.duration.seconds
          @new_intervention.working_periods << duplicate_working_period
        end

        @intervention.group_parameters.each do |group_parameter|
          duplicate_group_parameter = group_parameter.dup
          duplicate_group_parameter.intervention = @new_intervention

          [:doers, :inputs, :outputs, :targets, :tools].each do |k|
            group_parameter.send(k).each do |parameter|
              duplicate_parameter = create_duplicate_parameter(parameter, attrs)
              duplicate_parameter.group = duplicate_group_parameter
              duplicate_parameter.intervention = @new_intervention
              duplicate_group_parameter.send(k) << duplicate_parameter
            end
          end

          @new_intervention.group_parameters << duplicate_group_parameter
        end

        @intervention.product_parameters.where(group_id: nil).each do |parameter|
          duplicate_parameter = create_duplicate_parameter(parameter, attrs)
          duplicate_parameter.intervention = @new_intervention
          @new_intervention.product_parameters << duplicate_parameter
        end

        @intervention.participations.each do |participation|
          duplicate_participation = participation.dup
          duplicate_participation.intervention = @new_intervention

          participation.working_periods.each do |working_period|
            duplicate_working_period = working_period.dup
            duplicate_working_period.intervention_participation = duplicate_participation
            duplicate_working_period.started_at = duplicate_working_period.started_at.change(year: new_date.year, month: new_date.month, day: new_date.day) if new_date
            duplicate_working_period.stopped_at = duplicate_working_period.started_at + duplicate_working_period.duration.seconds
            duplicate_participation.working_periods << duplicate_working_period
          end

          @new_intervention.participations << duplicate_participation
        end
        @new_intervention.intervention_proposal_id = @intervention.intervention_proposal_id if @intervention.respond_to?(:intervention_proposal_id)
        @new_intervention
      end

      def find_intervention
        @intervention = Intervention.find(params[:intervention])
      end

      def create_duplicate_parameter(parameter, attributes)
        duplicate_parameter = parameter.dup
        %i[targets doers tools inputs outputs].each do |product_parameter|
          next unless "intervention_#{product_parameter}" == duplicate_parameter.class.name.underscore.pluralize

          attributes["#{product_parameter}_attributes"].each_value do |values|
            next unless parameter.id.to_s == values["id"]

            values.delete('id')
            duplicate_parameter.assign_attributes(values)
          end
        end
        duplicate_parameter
      end
  end
end
