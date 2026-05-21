# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::StoryImporter do
  before do
    SiteSetting.hacker_news_client_enabled = true
    SiteSetting.nested_replies_enabled = true
    SiteSetting.hacker_news_client_voter_pool_size = 5
    ::HackerNewsClient::CategorySeeder.ensure_category!
  end

  let(:hn_id) { 9_000_000 }

  def stub_firebase_item(id, payload)
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/#{id}.json").to_return(
      status: 200,
      body: payload.to_json,
    )
  end

  def stub_algolia_tree(id, payload)
    stub_request(:get, "https://hn.algolia.com/api/v1/items/#{id}").to_return(
      status: 200,
      body: payload.to_json,
    )
  end

  it "creates a topic with the HN url as featured_link and a onebox line in the body" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "dang",
        "title" => "Hello World",
        "url" => "https://example.com/article",
        "time" => 1_600_000_000,
        "kids" => [],
      },
    )
    stub_algolia_tree(hn_id, { "id" => hn_id, "children" => [] })

    post = described_class.new(hn_id).import!

    expect(post).to be_present
    topic = post.topic
    expect(topic.title).to eq("Hello World")
    expect(topic.featured_link).to eq("https://example.com/article")
    expect(topic.custom_fields["hn_id"]).to eq(hn_id)
    expect(post.raw).to include("https://example.com/article")
    expect(post.raw).to include("Discuss on Hacker News")
    expect(post.user.custom_fields["hn_username"]).to eq("dang")
  end

  it "creates an Ask HN topic with no featured_link and the text body" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Ask HN: anything?",
        "text" => "<p>Body here</p>",
        "time" => 1_600_000_000,
        "kids" => [],
      },
    )
    stub_algolia_tree(hn_id, { "id" => hn_id, "children" => [] })

    post = described_class.new(hn_id).import!
    expect(post.topic.featured_link).to be_blank
    expect(post.raw).to include("Body here")
  end

  it "imports child comments in Firebase kids order with proper parent-of relationships" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Top story",
        "url" => "https://example.com",
        "time" => 1_600_000_000,
        "kids" => [101, 102],
      },
    )
    stub_algolia_tree(
      hn_id,
      {
        "id" => hn_id,
        "children" => [
          {
            "id" => 101,
            "author" => "alice",
            "text" => "First comment",
            "created_at_i" => 1_600_000_100,
            "children" => [
              {
                "id" => 103,
                "author" => "carol",
                "text" => "Reply to alice",
                "created_at_i" => 1_600_000_200,
                "children" => [],
              },
            ],
          },
          {
            "id" => 102,
            "author" => "bob",
            "text" => "Second comment",
            "created_at_i" => 1_600_000_150,
            "children" => [],
          },
        ],
      },
    )

    described_class.new(hn_id).import!

    topic = ::HackerNewsClient::Lookup.topic_for(hn_id)
    expect(topic).to be_present

    first_comment = ::HackerNewsClient::Lookup.post_for(101)
    second_comment = ::HackerNewsClient::Lookup.post_for(102)
    nested_reply = ::HackerNewsClient::Lookup.post_for(103)

    expect(first_comment.reply_to_post_number).to eq(1)
    expect(second_comment.reply_to_post_number).to eq(1)
    expect(nested_reply.reply_to_post_number).to eq(first_comment.post_number)

    expect(first_comment.custom_fields["hn_rank"]).to eq(0)
    expect(second_comment.custom_fields["hn_rank"]).to eq(1)
  end

  it "enqueues Firebase sync for kids missing from the Algolia tree" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Top story",
        "url" => "https://example.com",
        "time" => 1_600_000_000,
        "kids" => [101],
      },
    )
    stub_algolia_tree(hn_id, { "id" => hn_id, "children" => [] })

    expect { described_class.new(hn_id).import! }.to change {
      Jobs::HackerNewsClient::SyncItem.jobs.length
    }.by(1)

    enqueued_id = Jobs::HackerNewsClient::SyncItem.jobs.last["args"].first["hn_id"]
    expect(enqueued_id).to eq(101)
  end

  it "repairs missing comments when the topic already exists" do
    existing_post = Fabricate(:post)
    existing_post.topic.custom_fields["hn_id"] = hn_id
    existing_post.topic.save_custom_fields
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Top story",
        "url" => "https://example.com",
        "time" => 1_600_000_000,
        "kids" => [101],
      },
    )
    stub_algolia_tree(
      hn_id,
      {
        "id" => hn_id,
        "children" => [
          {
            "id" => 101,
            "author" => "alice",
            "text" => "First comment",
            "created_at_i" => 1_600_000_100,
            "children" => [],
          },
        ],
      },
    )

    expect { described_class.new(hn_id).import! }.to change { Post.count }.by(1)
    expect(::HackerNewsClient::Lookup.post_for(101)).to be_present
  end

  it "rechecks for an existing comment inside the item mutex" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Top story",
        "url" => "https://example.com",
        "time" => 1_600_000_000,
        "kids" => [101],
      },
    )
    stub_algolia_tree(
      hn_id,
      {
        "id" => hn_id,
        "children" => [
          {
            "id" => 101,
            "author" => "alice",
            "text" => "First comment",
            "created_at_i" => 1_600_000_100,
            "children" => [],
          },
        ],
      },
    )
    existing_post = Fabricate(:post)

    allow(::HackerNewsClient::Lookup).to receive(:post_for).and_call_original
    allow(::HackerNewsClient::Lookup).to receive(:post_for).with(101).and_return(nil, existing_post)

    expect { described_class.new(hn_id).import! }.to change { Post.count }.by(1)
    expect(::HackerNewsClient::Lookup.post_for(101)).to eq(existing_post)
  end

  it "does not import descendants under an existing trashed comment" do
    stub_firebase_item(
      hn_id,
      {
        "id" => hn_id,
        "type" => "story",
        "by" => "pg",
        "title" => "Top story",
        "url" => "https://example.com",
        "time" => 1_600_000_000,
        "kids" => [101],
      },
    )
    stub_algolia_tree(
      hn_id,
      {
        "id" => hn_id,
        "children" => [
          {
            "id" => 101,
            "author" => "alice",
            "text" => "First comment",
            "created_at_i" => 1_600_000_100,
            "children" => [
              {
                "id" => 102,
                "author" => "bob",
                "text" => "Nested reply",
                "created_at_i" => 1_600_000_200,
                "children" => [],
              },
            ],
          },
        ],
      },
    )
    trashed_post = Fabricate(:post)
    trashed_post.custom_fields["hn_id"] = "101"
    trashed_post.save_custom_fields
    PostDestroyer.new(Discourse.system_user, trashed_post, context: "test").destroy

    expect { described_class.new(hn_id).import! }.to change { Post.count }.by(1)
    expect(::HackerNewsClient::Lookup.post_for(102)).to be_nil
  end

  it "skips dead or deleted stories" do
    stub_firebase_item(hn_id, { "id" => hn_id, "type" => "story", "dead" => true })

    expect(described_class.new(hn_id).import!).to be_nil
    expect(::HackerNewsClient::Lookup.topic_for(hn_id)).to be_nil
  end
end
