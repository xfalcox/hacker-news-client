# frozen_string_literal: true

module ::Jobs
  module HackerNewsClient
    class FetchArticle < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.hacker_news_client_enabled
        return unless SiteSetting.hacker_news_client_fetch_articles

        topic_id = args[:topic_id]
        return if topic_id.blank?

        topic = Topic.find_by(id: topic_id)
        return unless topic

        ::HackerNewsClient::ArticleEmbedder.embed!(topic)
      end
    end
  end
end
