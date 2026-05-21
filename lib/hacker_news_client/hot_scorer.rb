# frozen_string_literal: true

module ::HackerNewsClient
  # Writes `topic_hot_scores.score` directly from HN's ranked list so /hot
  # mirrors HN's homepage order exactly. Scores are set well above what
  # Discourse's natural algorithm can produce (~0–100), so HN-ranked topics
  # always dominate. Topics that have fallen off the current HN list and were
  # previously scored by this module are zeroed back out.
  module HotScorer
    BASE_SCORE = 10_000_000.0
    RANKED_IDS_REDIS_KEY = "hacker_news_client:ranked_top_story_ids"
    RANKED_IDS_TTL = 1.hour

    module_function

    def remember_ranked(hn_ids)
      Discourse.redis.set(RANKED_IDS_REDIS_KEY, hn_ids.to_json, ex: RANKED_IDS_TTL.to_i)
    end

    def cached_ranked_ids
      JSON.parse(Discourse.redis.get(RANKED_IDS_REDIS_KEY) || "[]")
    rescue JSON::ParserError
      []
    end

    def apply!(ranked_hn_ids)
      ranked_hn_ids = Array(ranked_hn_ids).map(&:to_s)
      return if ranked_hn_ids.empty?

      hn_id_to_topic_id =
        TopicCustomField.where(name: "hn_id", value: ranked_hn_ids).pluck(:value, :topic_id).to_h

      now = Time.zone.now
      pairs = []
      ranked_hn_ids.each_with_index do |hn_id, rank|
        topic_id = hn_id_to_topic_id[hn_id]
        next unless topic_id
        pairs << [topic_id.to_i, BASE_SCORE - rank]
      end

      upsert_scores!(pairs, now) if pairs.present?
      zero_orphans!(pairs.map(&:first), now)

      TopicHotScore.recreate_hottest_topic_ids_cache
    end

    def upsert_scores!(pairs, now)
      values_sql = pairs.map { |topic_id, score| "(#{topic_id}, #{score})" }.join(", ")
      DB.exec(<<~SQL, now: now)
        INSERT INTO topic_hot_scores (
          topic_id, score, recent_likes, recent_posters, created_at, updated_at
        )
        SELECT v.topic_id, v.score, 0, 0, :now, :now
        FROM (VALUES #{values_sql}) AS v(topic_id, score)
        ON CONFLICT (topic_id) DO UPDATE
        SET score = EXCLUDED.score, updated_at = EXCLUDED.updated_at
      SQL
    end

    def zero_orphans!(current_topic_ids, now)
      excluded = current_topic_ids.presence || [0]
      DB.exec(<<~SQL, base: BASE_SCORE, ids: excluded, now: now)
        UPDATE topic_hot_scores
        SET score = 0, updated_at = :now
        WHERE score >= :base
          AND topic_id NOT IN (:ids)
      SQL
    end
  end
end
