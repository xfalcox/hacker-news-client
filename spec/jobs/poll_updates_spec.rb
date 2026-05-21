# frozen_string_literal: true

RSpec.describe ::Jobs::HackerNewsClient::PollUpdates do
  before { SiteSetting.hacker_news_client_enabled = true }

  it "enqueues SyncItem only for ids we already track" do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/updates.json").to_return(
      status: 200,
      body: { "items" => [100, 200, 300], "profiles" => [] }.to_json,
    )

    tracked_post = Fabricate(:post)
    tracked_post.custom_fields["hn_id"] = "100"
    tracked_post.save_custom_fields

    tracked_topic = Fabricate(:topic)
    tracked_topic.custom_fields["hn_id"] = "200"
    tracked_topic.save_custom_fields

    expect { described_class.new.execute(nil) }.to change {
      Jobs::HackerNewsClient::SyncItem.jobs.length
    }.by(2)

    enqueued_ids = Jobs::HackerNewsClient::SyncItem.jobs.map { |j| j["args"].first["hn_id"] }
    expect(enqueued_ids).to contain_exactly(100, 200)
  end
end
