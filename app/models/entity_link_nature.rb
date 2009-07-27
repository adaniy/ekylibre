# == Schema Information
#
# Table name: entity_link_natures
#
#  company_id   :integer       not null
#  created_at   :datetime      not null
#  creator_id   :integer       
#  id           :integer       not null, primary key
#  lock_version :integer       default(0), not null
#  name         :string(255)   not null
#  name_1_to_2  :string(255)   
#  name_2_to_1  :string(255)   
#  symmetric    :boolean       not null
#  updated_at   :datetime      not null
#  updater_id   :integer       
#

class EntityLinkNature < ActiveRecord::Base

  belongs_to :company
  has_many   :entity_links

  def available_nature
    self.symetric ? "" : self.name_2_to_1 
  end

end
 
