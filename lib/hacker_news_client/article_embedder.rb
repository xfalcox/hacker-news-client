# frozen_string_literal: true

module ::HackerNewsClient
  # Fetches the linked article for an imported story and stashes its extracted
  # text in a TopicEmbed row tied to the existing topic. discourse-ai reads
  # `topic.topic_embed.embed_content_cache` when building embeddings and
  # summaries, so this gives those features the full article instead of just
  # the HN title + comments.
  module ArticleEmbedder
    module_function

    def embed!(topic)
      return unless topic

      op = topic.first_post
      return unless op

      url = topic.featured_link.presence
      return if url.blank?

      normalized = TopicEmbed.normalize_url(url)

      # embed_url is globally unique; if another topic already owns this URL,
      # leave it alone rather than stealing the embed.
      existing = TopicEmbed.with_deleted.find_by(embed_url: normalized)
      return if existing && existing.topic_id != topic.id

      response = TopicEmbed.find_remote(url)
      return if response.nil? || response.body.blank?

      body = response.body.truncate(TopicEmbed::EMBED_CONTENT_CACHE_MAX_LENGTH)

      embed = existing || TopicEmbed.new
      embed.assign_attributes(
        topic_id: topic.id,
        post_id: op.id,
        embed_url: normalized,
        content_sha1: Digest::SHA1.hexdigest(body),
        embed_content_cache: body,
      )
      embed.save!

      Rails.logger.info(
        "HackerNewsClient: cached article embed for topic_id=#{topic.id} url=#{normalized}",
      )
      embed
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
