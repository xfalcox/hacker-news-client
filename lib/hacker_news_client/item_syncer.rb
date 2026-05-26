# frozen_string_literal: true

module ::HackerNewsClient
  class ItemSyncer
    def initialize(item, firebase: FirebaseClient.new)
      @item = item
      @firebase = firebase
    end

    def sync!
      return nil unless @item
      hn_id = @item["id"]
      return nil unless hn_id

      if @item["deleted"] || @item["dead"]
        soft_delete(hn_id)
        return nil
      end

      case @item["type"]
      when "story"
        sync_story_kids
      when "comment"
        sync_comment
      end
    end

    private

    def soft_delete(hn_id)
      post = Lookup.post_for(hn_id)
      return unless post && !post.trashed?

      PostDestroyer.new(Discourse.system_user, post, context: "Hacker News item deleted").destroy
      Rails.logger.info("HackerNewsClient: soft-deleted post_id=#{post.id} for HN #{hn_id}")
    end

    def sync_story_kids
      hn_id = @item["id"]
      topic = Lookup.topic_for(hn_id)
      return unless topic

      enqueue_unseen_kids(@item["kids"])
    end

    def sync_comment
      hn_id = @item["id"]
      post = Lookup.post_for(hn_id)
      if post&.trashed?
        Rails.logger.debug("HackerNewsClient: skipped trashed post for live HN #{hn_id}")
        return
      end

      if post
        update_existing(post)
      else
        create_new
      end

      enqueue_unseen_kids(@item["kids"])
    end

    def update_existing(post)
      raw = HtmlToMarkdown.new(@item["text"].to_s).to_markdown
      return if raw.blank?
      return if raw.strip == post.raw.to_s.strip

      revised =
        PostRevisor.new(post).revise!(
          Discourse.system_user,
          { raw: raw, edit_reason: I18n.t("hacker_news_client.edit_reason") },
          skip_validations: true,
          bypass_bump: true,
        )
      if revised
        Rails.logger.info("HackerNewsClient: revised post_id=#{post.id} for HN #{@item["id"]}")
      end
    end

    def create_new
      hn_id = @item["id"]
      return if Lookup.post_for(hn_id)

      DistributedMutex.synchronize("hacker_news_client:item:#{hn_id}", validity: 5.minutes) do
        return if Lookup.post_for(hn_id)

        create_new_with_lock
      end
    end

    def create_new_with_lock
      parent_id = @item["parent"]
      unless parent_id
        Rails.logger.debug("HackerNewsClient: skipped HN #{@item["id"]} with no parent")
        return
      end

      parent_post =
        Lookup.post_for(parent_id, include_trashed: false) ||
          Lookup.topic_for(parent_id)&.first_post
      unless parent_post
        Rails.logger.debug(
          "HackerNewsClient: skipped HN #{@item["id"]}; parent #{parent_id} not imported",
        )
        return
      end

      author = UserImporter.find_or_create_for_hn(@item["by"])
      raw = HtmlToMarkdown.new(@item["text"].to_s).to_markdown
      if raw.blank?
        Rails.logger.debug("HackerNewsClient: skipped HN #{@item["id"]} with blank text")
        return
      end

      created_at = @item["time"] ? Time.at(@item["time"].to_i) : Time.now

      fb_parent = @firebase.item(parent_id)
      kids = fb_parent && Array(fb_parent["kids"])
      rank = kids ? kids.index(@item["id"]) : nil
      if rank.nil?
        Rails.logger.debug(
          "HackerNewsClient: skipped HN #{@item["id"]}; could not resolve rank under parent #{parent_id}",
        )
        return
      end

      creator =
        PostCreator.new(
          author,
          topic_id: parent_post.topic_id,
          reply_to_post_number: parent_post.post_number,
          raw: raw,
          created_at: created_at,
          skip_validations: true,
          import_mode: true,
          custom_fields: {
            "hn_id" => @item["id"].to_s,
            "hn_rank" => rank.to_s,
          },
        )
      post = creator.create
      if creator.errors.present?
        Rails.logger.warn(
          "HackerNewsClient: failed to sync HN #{@item["id"]}: #{creator.errors.full_messages.join(", ")}",
        )
        return
      end

      # import_mode skips PostCreator's job enqueue, so links in the comment
      # body are never oneboxed. Trigger post-processing explicitly.
      post.trigger_post_process(new_post: true)

      Rails.logger.info(
        "HackerNewsClient: created post_id=#{post.id} for HN #{@item["id"]} parent_hn_id=#{parent_id} rank=#{rank}",
      )
    end

    def enqueue_unseen_kids(kids)
      enqueued_count = 0
      Array(kids).each do |kid_id|
        next if Lookup.post_for(kid_id)
        Jobs.enqueue(::Jobs::HackerNewsClient::SyncItem, hn_id: kid_id)
        enqueued_count += 1
      end
      if enqueued_count > 0
        Rails.logger.info(
          "HackerNewsClient: enqueued #{enqueued_count} unseen child sync jobs for HN #{@item["id"]}",
        )
      end
    end
  end
end
