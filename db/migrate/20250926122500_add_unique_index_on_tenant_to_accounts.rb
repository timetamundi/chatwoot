class AddUniqueIndexOnTenantToAccounts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def up
    execute <<~SQL
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_accounts_tenant_unique
      ON accounts (lower(custom_attributes->>'tenant_id'))
      WHERE (custom_attributes ? 'tenant_id');
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS idx_accounts_tenant_unique;
    SQL
  end
end
