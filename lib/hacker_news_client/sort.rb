# frozen_string_literal: true

module ::HackerNewsClient
  module Sort
    HN_RANK = "hn_rank"

    # Pulls `hn_rank` from post_custom_fields via a correlated subquery. The
    # `(post_id, name)` index on post_custom_fields keeps the per-row lookup
    # cheap; posts without an `hn_rank` (e.g. the OP) sort last.
    HN_RANK_SQL = <<~SQL.squish.freeze
      COALESCE(
        (
          SELECT NULLIF(post_custom_fields.value, '')::bigint
          FROM post_custom_fields
          WHERE post_custom_fields.post_id = posts.id
            AND post_custom_fields.name = 'hn_rank'
          LIMIT 1
        ),
        2147483647
      ) ASC, post_number ASC
    SQL

    UNRANKED = 2_147_483_647

    module_function

    # Preload hn_rank for a batch of posts in one query so per-post
    # custom_fields reads don't each hit the DB. No-op for posts that already
    # have it preloaded (the tree loader extension does this for the whole
    # level before sorting per parent group).
    def preload_ranks(posts)
      pending = posts.reject { |p| p.custom_field_preloaded?(HN_RANK) }
      Post.preload_custom_fields(pending, [HN_RANK]) if pending.present?
    end

    def rank_for(post)
      post.custom_fields[HN_RANK].presence&.to_i || UNRANKED
    end

    # Override NestedReplies::TreeLoader#load_posts_for_tree to preload hn_rank
    # for the whole batch up front. Without this, the per-parent-group
    # sort_in_memory calls would each issue their own query.
    module TreeLoaderExtension
      def load_posts_for_tree(scope)
        posts = super
        ::HackerNewsClient::Sort.preload_ranks(posts.to_a)
        posts
      end
    end

    module Extension
      def valid?(algorithm)
        algorithm == ::HackerNewsClient::Sort::HN_RANK || super
      end

      def sql_order_expression(algorithm)
        if algorithm == ::HackerNewsClient::Sort::HN_RANK
          return ::HackerNewsClient::Sort::HN_RANK_SQL
        end
        super
      end

      def sort_in_memory(posts, algorithm)
        if algorithm == ::HackerNewsClient::Sort::HN_RANK
          ::HackerNewsClient::Sort.preload_ranks(posts)
          return posts.sort_by { |p| [::HackerNewsClient::Sort.rank_for(p), p.post_number] }
        end
        super
      end
    end
  end
end
