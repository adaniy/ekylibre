class AddProcessableAttachmentToDocument < ActiveRecord::Migration
  def change
    add_column :documents, :processable_attachment, :boolean, null: false, default: true
  end
end
