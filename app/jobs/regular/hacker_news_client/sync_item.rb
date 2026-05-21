# frozen_string_literal: true

module ::Jobs
  module HackerNewsClient
    class SyncItem < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.hacker_news_client_enabled

        hn_id = args[:hn_id]
        return if hn_id.blank?

        firebase = ::HackerNewsClient::FirebaseClient.new
        item = firebase.item(hn_id)
        return unless item

        ::HackerNewsClient::ItemSyncer.new(item, firebase: firebase).sync!
      end
    end
  end
end
