# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::HotScorer do
  fab!(:topic_a, :topic)
  fab!(:topic_b, :topic)
  fab!(:topic_c, :topic)

  before do
    topic_a.custom_fields["hn_id"] = "100"
    topic_a.save_custom_fields
    topic_b.custom_fields["hn_id"] = "200"
    topic_b.save_custom_fields
    topic_c.custom_fields["hn_id"] = "300"
    topic_c.save_custom_fields
  end

  describe ".apply!" do
    it "writes descending hot scores in HN rank order" do
      described_class.apply!([200, 100, 300])

      score_a = TopicHotScore.find_by(topic_id: topic_a.id).score
      score_b = TopicHotScore.find_by(topic_id: topic_b.id).score
      score_c = TopicHotScore.find_by(topic_id: topic_c.id).score

      expect(score_b).to be > score_a
      expect(score_a).to be > score_c
      expect(score_b).to eq(described_class::BASE_SCORE)
      expect(score_a).to eq(described_class::BASE_SCORE - 1)
      expect(score_c).to eq(described_class::BASE_SCORE - 2)
    end

    it "updates an existing topic_hot_scores row in place" do
      TopicHotScore.create!(topic_id: topic_a.id, score: 42.0)

      expect { described_class.apply!([100]) }.not_to change { TopicHotScore.count }

      expect(TopicHotScore.find_by(topic_id: topic_a.id).score).to eq(described_class::BASE_SCORE)
    end

    it "zeros previously-scored topics that fall off the list" do
      TopicHotScore.create!(topic_id: topic_a.id, score: described_class::BASE_SCORE)

      described_class.apply!([200])

      expect(TopicHotScore.find_by(topic_id: topic_a.id).score).to eq(0)
      expect(TopicHotScore.find_by(topic_id: topic_b.id).score).to eq(described_class::BASE_SCORE)
    end

    it "leaves topics with non-HN scores alone" do
      non_hn_topic = Fabricate(:topic)
      TopicHotScore.create!(topic_id: non_hn_topic.id, score: 5.0)

      described_class.apply!([100])

      expect(TopicHotScore.find_by(topic_id: non_hn_topic.id).score).to eq(5.0)
    end

    it "is a no-op for empty input" do
      expect { described_class.apply!([]) }.not_to raise_error
      expect(TopicHotScore.count).to eq(0)
    end

    it "skips hn_ids without an imported topic" do
      described_class.apply!([100, 999_999_999])
      expect(TopicHotScore.find_by(topic_id: topic_a.id).score).to eq(described_class::BASE_SCORE)
      expect(TopicHotScore.count).to eq(1)
    end
  end

  describe "ranked-id cache" do
    it "round-trips through Redis" do
      described_class.remember_ranked([1, 2, 3])
      expect(described_class.cached_ranked_ids).to eq([1, 2, 3])
    end

    it "returns an empty array when nothing is cached" do
      expect(described_class.cached_ranked_ids).to eq([])
    end
  end
end
