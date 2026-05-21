# frozen_string_literal: true

# name: hacker-news-client
# about: Mirrors the Hacker News front page into a Discourse category with nested comments
# version: 0.1
# authors: Discourse
# url: https://github.com/discourse/discourse/tree/main/plugins/hacker-news-client

enabled_site_setting :hacker_news_client_enabled

module ::HackerNewsClient
  PLUGIN_NAME = "hacker-news-client"
end

require_relative "lib/hacker_news_client/engine"

after_initialize do
  register_topic_custom_field_type("hn_id", :integer)
  register_topic_custom_field_type("hn_sync_state", :json)
  register_post_custom_field_type("hn_id", :integer)
  register_post_custom_field_type("hn_rank", :integer)
  register_user_custom_field_type("hn_username", :string)

  ::HackerNewsClient::CategorySeeder.ensure_category! if SiteSetting.hacker_news_client_enabled

  on(:site_setting_changed) do |name, _old, new_value|
    if name == :hacker_news_client_enabled && new_value
      ::HackerNewsClient::CategorySeeder.ensure_category!
    end
  end
end
