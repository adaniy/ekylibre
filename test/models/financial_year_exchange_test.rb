# = Informations
#
# == License
#
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2008-2009 Brice Texier, Thibaud Merigon
# Copyright (C) 2010-2012 Brice Texier
# Copyright (C) 2012-2014 Brice Texier, David Joulin
# Copyright (C) 2015-2021 Ekylibre SAS
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
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: financial_year_exchanges
#
#  analytical_codes                  :boolean          default(FALSE), not null
#  closed_at                         :datetime
#  created_at                        :datetime         not null
#  creator_id                        :integer
#  financial_year_id                 :integer          not null
#  format                            :string           default("ekyagri"), not null
#  id                                :integer          not null, primary key
#  import_file_content_type          :string
#  import_file_file_name             :string
#  import_file_file_size             :integer
#  import_file_updated_at            :datetime
#  lock_version                      :integer          default(0), not null
#  public_token                      :string
#  public_token_expired_at           :datetime
#  started_on                        :date             not null
#  stopped_on                        :date             not null
#  transmit_isacompta_analytic_codes :boolean          default(FALSE)
#  updated_at                        :datetime         not null
#  updater_id                        :integer
#
require 'test_helper'

class FinancialYearExchangeTest < Ekylibre::Testing::ApplicationTestCase::WithFixtures
  test_model_actions

  test 'opened scope includes opened exchanges' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year)
    assert FinancialYearExchange.opened.pluck(:id).include?(exchange.id)
  end

  test 'opened scope does not include closed exchanges' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, financial_year: financial_year)
    refute FinancialYearExchange.opened.pluck(:id).include?(exchange.id)
  end

  test 'closed scope includes closed exchanges' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, financial_year: financial_year)
    assert FinancialYearExchange.closed.pluck(:id).include?(exchange.id)
  end

  test 'closed scope does not include opened exchanges' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year)
    refute FinancialYearExchange.closed.pluck(:id).include?(exchange.id)
  end

  test 'for_public_token returns the exchange when the token is not expired' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year, public_token: '123ABC', public_token_expired_at: Time.zone.today + 1.day)
    assert_equal exchange, FinancialYearExchange.for_public_token('123ABC')
  end

  test 'for_public_token raises when the token is expired' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year, public_token: '123ABC', public_token_expired_at: Time.zone.today - 1.day)
    assert_raises(ActiveRecord::RecordNotFound) do
      FinancialYearExchange.for_public_token(exchange.public_token)
    end
  end

  test 'is valid' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    assert exchange.valid?
  end

  # test 'initialize with stopped on set to yesterday' do
  #   yesterday = Time.zone.yesterday
  #   exchange = FinancialYearExchange.new
  #   assert_equal yesterday, exchange.stopped_on
  # end

  test 'does not initialize with stopped on set to yesterday when stopped on is filled' do
    today = Time.zone.today
    exchange = FinancialYearExchange.new(stopped_on: today)
    assert_equal today, exchange.stopped_on
  end

  test 'needs a stopped on' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    exchange.stopped_on = nil
    refute exchange.valid?
  end

  test 'stopped on is before financial year stopped on' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    exchange.stopped_on = exchange.financial_year.stopped_on + 1.day
    refute exchange.valid?
  end

  test 'needs a financial year' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    exchange.financial_year = nil
    refute exchange.valid?
  end

  test 'generates public token' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    refute exchange.public_token.present?
    exchange.generate_public_token!
    assert exchange.public_token.present?
  end

  test 'public token expires on is set to 1 month later' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    exchange.generate_public_token!
    assert exchange.public_token_expired_at.present?
    assert_equal Time.zone.today + 1.month, exchange.public_token_expired_at
  end

  test 'started on is not updated on update' do
    financial_year = financial_years(:financial_years_025)
    exchange = build(:financial_year_exchange, financial_year: financial_year)
    initial_started_on = exchange.started_on
    exchange.closed_at = Time.zone.now
    assert exchange.save
    assert_equal initial_started_on, exchange.started_on
  end

  test 'accountant_email is the accountant default email' do
    accountant = create(:entity, :accountant, :with_email)
    financial_year = financial_years(:financial_years_025)
    assert financial_year.update_column(:accountant_id, accountant.id)
    exchange = create(:financial_year_exchange, financial_year: financial_year)
    assert_equal accountant.default_email_address.coordinate, exchange.accountant_email
  end

  test 'has accountant email when the accountant has an email' do
    accountant = create(:entity, :accountant, :with_email)
    financial_year = financial_years(:financial_years_025)
    assert financial_year.update_column(:accountant_id, accountant.id)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year)
    accountant = exchange.accountant
    assert accountant, 'Accountant is missing'
    accountant.emails.delete_all if accountant.emails.any?
    assert exchange.accountant.emails.empty?
    refute exchange.accountant_email?
    accountant.emails.create!(coordinate: 'accountant@accounting.org')
    exchange.reload
    assert exchange.accountant_email?
  end

  test 'is opened without closed at' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year)
    assert exchange.closed_at.blank?
    assert exchange.opened?
  end

  test 'is not opened with closed at' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, financial_year: financial_year)
    assert exchange.closed_at.present?
    refute exchange.opened?
  end

  test 'it closes' do
    financial_year = financial_years(:financial_years_025)
    exchange = create(:financial_year_exchange, :opened, financial_year: financial_year)
    assert exchange.close!
    assert_equal exchange.reload.closed_at.to_date, Time.zone.today
  end

  test 'started_on should be after financial year started_on' do
    FinancialYear.delete_all
    fy = create(:financial_year, year: 2021)
    exchange = build(:financial_year_exchange, :opened, financial_year: fy, started_on: '15/12/2020', stopped_on: '01/02/2021')
    assert_not exchange.valid?
    exchange.started_on = '15/01/2021'
    assert exchange.valid?
  end

  def get_computed_started_on(exchange)
    exchange.valid?
    exchange.started_on
  end
end
