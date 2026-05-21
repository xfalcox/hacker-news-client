# frozen_string_literal: true

class AddHnCustomFieldIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :topic_custom_fields,
                 name: "idx_tcf_hn_id",
                 algorithm: :concurrently,
                 if_exists: true
    add_index(
      :topic_custom_fields,
      :value,
      where: "name = 'hn_id'",
      name: "idx_tcf_hn_id",
      algorithm: :concurrently,
    )

    remove_index :post_custom_fields,
                 name: "idx_pcf_hn_id",
                 algorithm: :concurrently,
                 if_exists: true
    add_index(
      :post_custom_fields,
      :value,
      where: "name = 'hn_id'",
      name: "idx_pcf_hn_id",
      algorithm: :concurrently,
    )

    remove_index :user_custom_fields,
                 name: "idx_ucf_hn_username",
                 algorithm: :concurrently,
                 if_exists: true
    add_index(
      :user_custom_fields,
      :value,
      where: "name = 'hn_username'",
      name: "idx_ucf_hn_username",
      algorithm: :concurrently,
    )
  end

  def down
    remove_index :topic_custom_fields,
                 name: "idx_tcf_hn_id",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :post_custom_fields,
                 name: "idx_pcf_hn_id",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :user_custom_fields,
                 name: "idx_ucf_hn_username",
                 algorithm: :concurrently,
                 if_exists: true
  end
end
