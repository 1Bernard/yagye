class AddDeactivatedAtToSsoConfigurations < ActiveRecord::Migration[8.1]
  def change
    add_column :sso_configurations, :deactivated_at, :datetime
    add_index  :sso_configurations, :deactivated_at
  end
end
