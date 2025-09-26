class AddUniqueIndexToAccountUsers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    add_index :account_users, [:account_id, :user_id],
              unique: true,
              name: :idx_account_users_account_user_unique,
              algorithm: :concurrently
  end
end
