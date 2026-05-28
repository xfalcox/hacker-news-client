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

    # Bulk-load hn_rank for a batch of posts in one query, so the in-memory
    # sort doesn't trigger a per-post custom_fields load (N+1).
    def ranks_for(posts)
      ids = posts.map(&:id)
      return {} if ids.empty?

      PostCustomField
        .where(post_id: ids, name: HN_RANK)
        .pluck(:post_id, :value)
        .each_with_object({}) do |(post_id, value), memo|
          memo[post_id] = value.presence&.to_i || UNRANKED
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
          ranks = ::HackerNewsClient::Sort.ranks_for(posts)
          return(
            posts.sort_by { |p| [ranks[p.id] || ::HackerNewsClient::Sort::UNRANKED, p.post_number] }
          )
        end
        super
      end
    end
  end
end
