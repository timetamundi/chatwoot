class AddExternalIdToAccounts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :accounts, :external_id, :string
    add_index  :accounts, :external_id, unique: true, algorithm: :concurrently

    return unless ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM accounts').to_i == 1

    ext_id = ENV.fetch('DEFAULT_ACCOUNT_EXTERNAL_ID', 'DEV-001')
    execute "UPDATE accounts SET external_id='#{ext_id}' WHERE external_id IS NULL"
  end

  def down
    remove_index  :accounts, :external_id if index_exists?(:accounts, :external_id)
    remove_column :accounts, :external_id if column_exists?(:accounts, :external_id)
  end
end
