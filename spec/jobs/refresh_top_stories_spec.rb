# frozen_string_literal: true

RSpec.describe ::Jobs::HackerNewsClient::RefreshTopStories do
  before do
    SiteSetting.hacker_news_client_enabled = true
    ::HackerNewsClient::CategorySeeder.ensure_category!
  end

  it "enqueues ImportStory only for unknown stories" do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json").to_return(
      status: 200,
      body: [10, 20, 30].to_json,
    )

    existing_topic = Fabricate(:topic)
    existing_topic.custom_fields["hn_id"] = "20"
    existing_topic.save_custom_fields

    expect { described_class.new.execute(nil) }.to change {
      Jobs::HackerNewsClient::ImportStory.jobs.length
    }.by(2)

    enqueued_ids = Jobs::HackerNewsClient::ImportStory.jobs.map { |j| j["args"].first["hn_id"] }
    expect(enqueued_ids).to contain_exactly(10, 30)
  end

  it "does nothing when the plugin is disabled" do
    SiteSetting.hacker_news_client_enabled = false
    expect { described_class.new.execute(nil) }.not_to change {
      Jobs::HackerNewsClient::ImportStory.jobs.length
    }
  end
end
