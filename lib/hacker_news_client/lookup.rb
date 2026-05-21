# frozen_string_literal: true

module ::HackerNewsClient
  module Lookup
    module_function

    def topic_for(hn_id)
      Topic.joins(:_custom_fields).find_by(
        topic_custom_fields: {
          name: "hn_id",
          value: hn_id.to_s,
        },
      )
    end

    def post_for(hn_id, include_trashed: true)
      scope = include_trashed ? Post.with_deleted : Post
      scope.joins(:_custom_fields).find_by(post_custom_fields: { name: "hn_id", value: hn_id.to_s })
    end

    def user_for_hn_username(hn_username)
      User.joins(:_custom_fields).find_by(
        user_custom_fields: {
          name: "hn_username",
          value: hn_username,
        },
      )
    end
  end
end
