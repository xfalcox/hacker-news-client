# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::ArticleEmbedder do
  fab!(:topic) { Fabricate(:topic, featured_link: "https://example.com/article") }
  fab!(:op) { Fabricate(:post, topic: topic, post_number: 1) }

  def stub_remote(body:, title: "Article", url: "https://example.com/article")
    response = TopicEmbed::FetchResponse.new
    response.title = title
    response.body = body
    response.url = url
    allow(TopicEmbed).to receive(:find_remote).and_return(response)
  end

  describe ".embed!" do
    it "creates a topic embed with the fetched article text" do
      stub_remote(body: "<p>The full article body</p>")

      expect { described_class.embed!(topic) }.to change { TopicEmbed.count }.by(1)

      embed = TopicEmbed.find_by(topic_id: topic.id)
      expect(embed.post_id).to eq(op.id)
      expect(embed.embed_url).to eq("https://example.com/article")
      expect(embed.embed_content_cache).to include("The full article body")
      expect(embed.content_sha1).to be_present
    end

    it "updates the existing embed in place on a second run" do
      stub_remote(body: "<p>First</p>")
      described_class.embed!(topic)

      stub_remote(body: "<p>Second</p>")
      expect { described_class.embed!(topic) }.not_to change { TopicEmbed.count }

      expect(TopicEmbed.find_by(topic_id: topic.id).embed_content_cache).to include("Second")
    end

    it "skips topics without a featured link" do
      topic.update!(featured_link: nil)
      expect { described_class.embed!(topic) }.not_to change { TopicEmbed.count }
    end

    it "skips when the remote fetch returns nothing" do
      allow(TopicEmbed).to receive(:find_remote).and_return(nil)
      expect { described_class.embed!(topic) }.not_to change { TopicEmbed.count }
    end

    it "does not steal an embed_url already owned by another topic" do
      other_topic = Fabricate(:topic)
      other_post = Fabricate(:post, topic: other_topic)
      TopicEmbed.create!(
        topic_id: other_topic.id,
        post_id: other_post.id,
        embed_url: "https://example.com/article",
        content_sha1: Digest::SHA1.hexdigest("x"),
      )

      stub_remote(body: "<p>body</p>")
      expect { described_class.embed!(topic) }.not_to change { TopicEmbed.count }
      expect(TopicEmbed.find_by(topic_id: topic.id)).to be_nil
    end

    it "truncates content to the model's cache limit" do
      stub_remote(body: "<p>#{"a" * 40_000}</p>")
      described_class.embed!(topic)

      cache = TopicEmbed.find_by(topic_id: topic.id).embed_content_cache
      expect(cache.length).to be <= TopicEmbed::EMBED_CONTENT_CACHE_MAX_LENGTH
    end
  end
end
