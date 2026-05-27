# frozen_string_literal: true

RSpec.describe ::Jobs::HackerNewsClient::FetchArticle do
  fab!(:topic) { Fabricate(:topic, featured_link: "https://example.com/article") }
  fab!(:op) { Fabricate(:post, topic: topic, post_number: 1) }

  before do
    SiteSetting.hacker_news_client_enabled = true
    allow(::HackerNewsClient::ArticleEmbedder).to receive(:embed!)
  end

  it "delegates to ArticleEmbedder for the topic" do
    described_class.new.execute(topic_id: topic.id)
    expect(::HackerNewsClient::ArticleEmbedder).to have_received(:embed!).with(topic)
  end

  it "does nothing when article fetching is disabled" do
    SiteSetting.hacker_news_client_fetch_articles = false
    described_class.new.execute(topic_id: topic.id)
    expect(::HackerNewsClient::ArticleEmbedder).not_to have_received(:embed!)
  end

  it "does nothing when the topic is missing" do
    described_class.new.execute(topic_id: -1)
    expect(::HackerNewsClient::ArticleEmbedder).not_to have_received(:embed!)
  end
end
