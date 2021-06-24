# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2013 David Joulin, Brice Texier
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
  class CampaignsController < Backend::BaseController
    manage_restfully except: :show

    before_action only: :show do
      if params[:current_campaign]
        campaign = Campaign.find_or_create_by!(harvest_year: params[:current_campaign])
      end
      redirect_to action: :show, id: campaign.id if campaign
    end

    after_action only: :show do
      @current_campaign = @campaign
      current_user.current_campaign = @current_campaign unless @current_campaign == false
    end

    unroll

    list do |t|
      t.action :edit
      t.action :destroy, if: :destroyable?
      t.column :name, url: true
      t.column :harvest_year
      t.column :closed
    end

    def show
      return unless @campaign = find_and_check(:campaign)

      @currency = Onoma::Currency.find(Preference[:currency])
      activities_of_campaign = Activity.of_campaign(@campaign)
      @availables_activities = Activity.availables.where.not(id: activities_of_campaign)
      @families = activities_of_campaign.order(:family).collect(&:family).uniq
      @activities = activities_of_campaign
                    .left_join_working_duration_of_campaign(current_campaign)
                    .left_join_issues_count_of_campaign(current_campaign)
                    .left_join_production_costs_of_campaign(current_campaign)
      t3e(@campaign.attributes)
    end

    def open
      return unless (@campaign = find_and_check)

      activity = Activity.find(params[:activity_id])
      activity.budgets.find_or_create_by!(campaign: @campaign)
      redirect_to params[:redirect] || { action: :show, id: @campaign.id }
    end

    def close
      return unless (@campaign = find_and_check)

      activity = Activity.find(params[:activity_id])
      raise 'Cannot close used activity' if activity.productions.of_campaign(@campaign).any?

      activity_budget = activity.budgets.find_by(campaign: @campaign)
      activity_budget.destroy if activity_budget
      redirect_to params[:redirect] || { action: :show, id: @campaign.id }
    end

    def current
      if current_campaign.blank?
        @current_campaign = Campaign.find_or_create_by!(harvest_year: Date.current.year)
        current_user.current_campaign = @current_campaign
      end
      redirect_to backend_campaign_path(current_campaign)
    end
  end
end
