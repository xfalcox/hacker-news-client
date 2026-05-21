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
          return posts.sort_by { |p| [p.custom_fields["hn_rank"].to_i, p.post_number] }
        end
        super
      end
    end
  end
end
