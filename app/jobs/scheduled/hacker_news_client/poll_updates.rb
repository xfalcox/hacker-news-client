# frozen_string_literal: true

module ::Jobs
  module HackerNewsClient
    class PollUpdates < ::Jobs::Scheduled
      every 1.minute
      cluster_concurrency 1

      def execute(_args)
        return unless SiteSetting.hacker_news_client_enabled

        firebase = ::HackerNewsClient::FirebaseClient.new
        payload = firebase.updates || {}
        ids = Array(payload["items"])

        known_ids = known_imported_ids(ids)
        enqueued_count = 0
        ids.each do |hn_id|
          next if known_ids.exclude?(hn_id.to_s)
          ::Jobs.enqueue(::Jobs::HackerNewsClient::SyncItem, hn_id: hn_id)
          enqueued_count += 1
        end
        if enqueued_count > 0
          Rails.logger.info(
            "HackerNewsClient: polled updates fetched=#{ids.length} enqueued=#{enqueued_count}",
          )
        end
      end

      private

      def known_imported_ids(ids)
        return Set.new if ids.empty?
        values = ids.map(&:to_s)
        topic_ids = TopicCustomField.where(name: "hn_id", value: values).pluck(:value)
        post_ids = PostCustomField.where(name: "hn_id", value: values).pluck(:value)
        (topic_ids + post_ids).to_set
      end
    end
  end
end
