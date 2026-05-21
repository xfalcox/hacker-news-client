# frozen_string_literal: true

module ::Jobs
  module HackerNewsClient
    class RefreshTopStories < ::Jobs::Scheduled
      every 1.minute
      cluster_concurrency 1

      def execute(_args)
        return unless SiteSetting.hacker_news_client_enabled

        firebase = ::HackerNewsClient::FirebaseClient.new
        limit = SiteSetting.hacker_news_client_top_stories_count
        ids = firebase.top_stories.first(limit)

        enqueued_count = 0
        ids.each do |hn_id|
          next if ::HackerNewsClient::Lookup.topic_for(hn_id)
          ::Jobs.enqueue(::Jobs::HackerNewsClient::ImportStory, hn_id: hn_id)
          enqueued_count += 1
        end
        if enqueued_count > 0
          Rails.logger.info(
            "HackerNewsClient: refreshed top stories fetched=#{ids.length} enqueued=#{enqueued_count}",
          )
        end
      end
    end
  end
end
