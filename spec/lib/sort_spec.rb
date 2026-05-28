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
  end
end
