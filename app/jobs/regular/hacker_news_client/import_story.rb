# frozen_string_literal: true

module ::Jobs
  module HackerNewsClient
    class ImportStory < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.hacker_news_client_enabled

        hn_id = args[:hn_id]
        return if hn_id.blank?

        ::HackerNewsClient::StoryImporter.new(hn_id).import!
      end
    end
  end
end
