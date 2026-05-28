# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::Sort do
  fab!(:topic)
  fab!(:op) { Fabricate(:post, topic: topic, post_number: 1) }
  fab!(:a) { Fabricate(:post, topic: topic) }
  fab!(:b) { Fabricate(:post, topic: topic) }
  fab!(:c) { Fabricate(:post, topic: topic) }
  fab!(:unranked) { Fabricate(:post, topic: topic) }

  before do
    a.custom_fields["hn_rank"] = "2"
    a.save_custom_fields
    b.custom_fields["hn_rank"] = "0"
    b.save_custom_fields
    c.custom_fields["hn_rank"] = "1"
    c.save_custom_fields
  end

  describe "registration" do
    it "advertises hn_rank as a valid algorithm" do
      expect(::NestedReplies::Sort.valid?("hn_rank")).to eq(true)
    end
  end

  describe "SQL ordering" do
    it "orders ranked posts ascending and pushes unranked to the end" do
      ordered = ::NestedReplies::Sort.apply(topic.posts, "hn_rank").pluck(:id)

      ranked_segment = ordered.first(3)
      expect(ranked_segment).to eq([b.id, c.id, a.id])

      tail = ordered.last(2)
      expect(tail).to contain_exactly(op.id, unranked.id)
      expect(ordered.index(op.id)).to be < ordered.index(unranked.id)
    end
  end

  describe "in-memory ordering" do
    it "orders by hn_rank ascending then post_number" do
      sorted = ::NestedReplies::Sort.sort_in_memory(topic.posts.to_a, "hn_rank")
      ranked_only = sorted.select { |p| p.custom_fields["hn_rank"].present? }
      expect(ranked_only.map(&:id)).to eq([b.id, c.id, a.id])
    end

    it "loads ranks in a single query (no N+1 over custom_fields)" do
      posts = topic.posts.to_a # custom_fields not preloaded

      queries = track_sql_queries { ::NestedReplies::Sort.sort_in_memory(posts, "hn_rank") }

      pcf_queries = queries.select { |q| q.include?("post_custom_fields") }
      expect(pcf_queries.size).to eq(1)
    end

    it "issues no further queries when ranks are already preloaded" do
      posts = topic.posts.to_a
      ::HackerNewsClient::Sort.preload_ranks(posts)

      queries = track_sql_queries { ::NestedReplies::Sort.sort_in_memory(posts, "hn_rank") }

      expect(queries.select { |q| q.include?("post_custom_fields") }).to be_empty
    end
  end

  describe "tree loader integration" do
    it "preloads hn_rank so a full tree render avoids per-group rank queries" do
      parent = Fabricate(:post, topic: topic, reply_to_post_number: nil)
      5.times do |i|
        child = Fabricate(:post, topic: topic, reply_to_post_number: parent.post_number)
        child.custom_fields["hn_rank"] = i.to_s
        child.save_custom_fields
      end

      loader = ::NestedReplies::TreeLoader.new(topic: topic, guardian: Guardian.new)

      queries = track_sql_queries { loader.batch_preload_tree([parent], "hn_rank", max_depth: 3) }

      # The hn_rank SQL ordering uses a correlated subquery (unquoted
      # `FROM post_custom_fields`); the association preload is the only query
      # that selects directly `FROM "post_custom_fields"`.
      preload_queries = queries.select { |q| q.include?('FROM "post_custom_fields"') }
      expect(preload_queries.size).to be <= 1
    end
  end
end
