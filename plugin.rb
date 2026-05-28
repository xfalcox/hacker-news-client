# frozen_string_literal: true

# name: hacker-news-client
# about: DEMO SITES ONLY — mirrors the Hacker News front page into a Discourse category with nested comments. Not for production forums.
# version: 0.1
# authors: Discourse
# url: https://github.com/xfalcox/hacker-news-client

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

  ::NestedReplies::Sort.singleton_class.prepend(::HackerNewsClient::Sort::Extension)
  ::NestedReplies::TreeLoader.prepend(::HackerNewsClient::Sort::TreeLoaderExtension)
  ::NestedTopicsController.prepend(::HackerNewsClient::NestedTopicsControllerExtension)

  # Extend the core enum so `nested_replies_default_sort = "hn_rank"` validates.
  # The seeder uses this to flip the global default when the plugin first activates.
  choices = SiteSetting.type_supervisor.instance_variable_get(:@choices)
  if choices[:nested_replies_default_sort] &&
       choices[:nested_replies_default_sort].exclude?(::HackerNewsClient::Sort::HN_RANK)
    choices[:nested_replies_default_sort] << ::HackerNewsClient::Sort::HN_RANK
  end

  ::HackerNewsClient::CategorySeeder.ensure_category! if SiteSetting.hacker_news_client_enabled

  on(:site_setting_changed) do |name, _old, new_value|
    if name == :hacker_news_client_enabled && new_value
      ::HackerNewsClient::CategorySeeder.ensure_category!
    end
  end

  # Discourse's UpdateTopicHotScores scheduled job overwrites topic_hot_scores
  # every 10 minutes. Re-apply HN-driven scores immediately after, using the
  # most recent ranked list cached by RefreshTopStories.
  on(:topic_hot_scores_updated) do
    next unless SiteSetting.hacker_news_client_enabled
    ids = ::HackerNewsClient::HotScorer.cached_ranked_ids
    ::HackerNewsClient::HotScorer.apply!(ids) if ids.any?
  end
end
