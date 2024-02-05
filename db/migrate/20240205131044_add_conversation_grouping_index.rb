class AddConversationGroupingIndex < ActiveRecord::Migration[7.0]
  def change
    add_index(
      :conversations,
      "(additional_attributes->>'grouping_key')",
      name: 'index_conversations_on_additional_attributes_grouping_key'
    )
  end
end
