# frozen_string_literal: true

module ::HackerNewsClient
  class RankLiker
    def initialize(topic)
      @topic = topic
    end

    def apply_to_all_sibling_groups!
      sibling_groups.each { |parent_post_number, posts| apply_to_group!(parent_post_number, posts) }
    end

    def apply_to_sibling_group_of!(post)
      parent_pn = post.reply_to_post_number
      group = ordered_siblings(parent_pn)
      apply_to_group!(parent_pn, group)
    end

    private

    def sibling_groups
      @topic
        .posts
        .where("post_number > 1")
        .where.not(reply_to_post_number: nil)
        .group_by(&:reply_to_post_number)
    end

    def ordered_siblings(parent_post_number)
      @topic.posts.where(reply_to_post_number: parent_post_number).to_a
    end

    def voter_pool
      @voter_pool ||= UserImporter.voter_pool
    end

    def apply_to_group!(_parent_pn, posts)
      pool = voter_pool
      pool_size = pool.length
      return if pool_size.zero?

      sorted =
        posts.sort_by do |post|
          rank = post.custom_fields["hn_rank"]
          rank.present? ? rank.to_i : Float::INFINITY
        end

      sorted.each_with_index do |post, rank|
        target = [pool_size - rank, 0].max
        adjust_likes(post, pool, target)
      end
    end

    def adjust_likes(post, pool, target)
      existing_voter_ids =
        PostAction
          .where(post_id: post.id, post_action_type_id: PostActionType.types[:like])
          .where(user_id: pool.map(&:id))
          .pluck(:user_id)
          .to_set

      pool.each_with_index do |voter, i|
        should_like = i < target
        currently_likes = existing_voter_ids.include?(voter.id)

        next if should_like == currently_likes

        if should_like
          PostActionCreator.like(voter, post, true)
        else
          PostActionDestroyer.destroy(voter, post, :like)
        end
      end
    end
  end
end
