# frozen_string_literal: true

module ::HackerNewsClient
  class StoryImporter
    def initialize(hn_id, firebase: FirebaseClient.new, algolia: AlgoliaClient.new)
      @hn_id = hn_id.to_i
      @firebase = firebase
      @algolia = algolia
    end

    def import!
      DistributedMutex.synchronize("hacker_news_client:story:#{@hn_id}", validity: 5.minutes) do
        import_with_lock
      end
    end

    private

    def import_with_lock
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stats = Hash.new(0)

      story = @firebase.item(@hn_id)
      return nil unless story
      if story["deleted"] || story["dead"]
        Rails.logger.info("HackerNewsClient: skipped dead/deleted story HN #{@hn_id}")
        return nil
      end
      if story["type"] != "story"
        Rails.logger.info("HackerNewsClient: skipped non-story item HN #{@hn_id}")
        return nil
      end
      if story["title"].blank?
        Rails.logger.info("HackerNewsClient: skipped story HN #{@hn_id} with blank title")
        return nil
      end

      existing_topic = Lookup.topic_for(@hn_id)
      topic_post =
        if existing_topic
          stats[:existing_topic] += 1
          existing_topic.first_post
        else
          author = UserImporter.find_or_create_for_hn(story["by"])
          create_topic_post(story, author)
        end
      return nil unless topic_post

      # PostCreator with import_mode: true skips :topic_created events, so the
      # NestedTopic record (normally minted by config/initializers/300-nested-replies.rb)
      # needs to be created explicitly.
      NestedTopic.find_or_create_by!(topic: topic_post.topic) if SiteSetting.nested_replies_enabled

      tree = @algolia.item_tree(@hn_id) || {}
      kids = Array(story["kids"])

      import_children(topic_post, kids, tree_index(tree), stats)

      # No synthetic likes during initial backfill: comments are created in HN's
      # ranked order and the nested-replies sort tiebreaks on post_number ASC,
      # so the initial render already matches HN. Likes are minted by ItemSyncer
      # only when a new comment arrives out-of-order under an existing parent.

      topic_post.topic.upsert_custom_fields(
        "hn_sync_state" => { "last_synced_at" => Time.now.to_i }.to_json,
      )

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      Rails.logger.info(
        "HackerNewsClient: imported story HN #{@hn_id} topic_id=#{topic_post.topic_id} " \
          "created_comments=#{stats[:created_comments]} existing_comments=#{stats[:existing_comments]} " \
          "missing_algolia_children=#{stats[:missing_algolia_children]} skipped_comments=#{stats[:skipped_comments]} " \
          "elapsed_ms=#{elapsed_ms}",
      )

      topic_post
    end

    def create_topic_post(story, author)
      raw_body = build_story_body(story)

      opts = {
        title: story["title"],
        raw: raw_body,
        category: CategorySeeder.category_id,
        created_at: Time.at(story["time"].to_i),
        skip_validations: true,
        import_mode: true,
        custom_fields: {
          "hn_id" => @hn_id.to_s,
        },
      }
      opts[:featured_link] = story["url"] if story["url"].present?

      creator = PostCreator.new(author, opts)
      post = creator.create
      if creator.errors.present?
        Rails.logger.warn(
          "HackerNewsClient: failed to create topic for HN #{@hn_id}: #{creator.errors.full_messages.join(", ")}",
        )
        return nil
      end

      # import_mode skips PostCreator's job enqueue, so the URL in the body is
      # never oneboxed. Trigger post-processing explicitly to cook the onebox.
      post.trigger_post_process(new_post: true)

      if story["url"].present?
        Jobs.enqueue(::Jobs::HackerNewsClient::FetchArticle, topic_id: post.topic_id)
      end

      Rails.logger.info(
        "HackerNewsClient: created topic for HN #{@hn_id} topic_id=#{post.topic_id}",
      )
      post
    end

    def build_story_body(story)
      parts = []
      parts << story["url"] if story["url"].present?
      if story["text"].present?
        parts << HtmlToMarkdown.new(story["text"]).to_markdown
      elsif story["url"].present?
        parts << I18n.t("hacker_news_client.link_only_body")
      end
      parts << "\n---\n#{I18n.t("hacker_news_client.footer", hn_id: @hn_id)}"
      parts.join("\n\n")
    end

    def tree_index(tree)
      index = {}
      stack = [tree]
      until stack.empty?
        node = stack.pop
        next unless node.is_a?(Hash)
        index[node["id"]] = node if node["id"]
        Array(node["children"]).each { |c| stack.push(c) }
      end
      index
    end

    # Walk the comment tree top-down using Firebase `kids` arrays (which preserve
    # HN's ranked order), filling in body content from the Algolia tree index.
    def import_children(parent_post, kids, index, stats)
      kids.each_with_index do |kid_id, rank|
        node = index[kid_id]
        unless node
          next if Lookup.post_for(kid_id)

          stats[:missing_algolia_children] += 1
          Rails.logger.info(
            "HackerNewsClient: enqueuing Firebase sync for HN #{kid_id} missing from Algolia tree",
          )
          Jobs.enqueue(::Jobs::HackerNewsClient::SyncItem, hn_id: kid_id)
          next
        end
        if node["text"].blank? || node["author"].blank?
          stats[:skipped_comments] += 1
          next
        end

        post = import_child(parent_post, node, kid_id, rank, stats)
        next unless post

        # Deeper levels follow Algolia's child order. HN's best-of ranking at
        # the top level is preserved via Firebase `kids`; recovering it for
        # every nested parent would cost one Firebase round-trip per node.
        grandkid_ids = Array(node["children"]).map { |c| c["id"] }
        import_children(post, grandkid_ids, index, stats)
      end
    end

    def import_child(parent_post, node, hn_id, rank, stats)
      existing_post = Lookup.post_for(hn_id)
      return nil if existing_post&.trashed?
      if existing_post
        stats[:existing_comments] += 1
        return existing_post
      end

      DistributedMutex.synchronize("hacker_news_client:item:#{hn_id}", validity: 5.minutes) do
        existing_post = Lookup.post_for(hn_id)
        return nil if existing_post&.trashed?
        if existing_post
          stats[:existing_comments] += 1
          return existing_post
        end

        commenter = UserImporter.find_or_create_for_hn(node["author"])
        post = create_comment(parent_post, commenter, node, hn_id, rank)
        stats[:created_comments] += 1 if post
        post
      end
    end

    def create_comment(parent_post, user, node, hn_id, rank)
      raw = HtmlToMarkdown.new(node["text"].to_s).to_markdown
      return nil if raw.blank?

      created_at = node["created_at_i"] ? Time.at(node["created_at_i"].to_i) : Time.now

      creator =
        PostCreator.new(
          user,
          topic_id: parent_post.topic_id,
          reply_to_post_number: parent_post.post_number,
          raw: raw,
          created_at: created_at,
          skip_validations: true,
          import_mode: true,
          custom_fields: {
            "hn_id" => hn_id.to_s,
            "hn_rank" => rank.to_s,
          },
        )
      post = creator.create
      if creator.errors.present?
        Rails.logger.warn(
          "HackerNewsClient: failed to create comment for HN #{hn_id}: #{creator.errors.full_messages.join(", ")}",
        )
        return nil
      end

      # import_mode skips PostCreator's job enqueue, so links in the comment
      # body are never oneboxed. Trigger post-processing explicitly.
      post.trigger_post_process(new_post: true)
      post
    end
  end
end
