# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::ItemSyncer do
  before do
    SiteSetting.hacker_news_client_enabled = true
    SiteSetting.nested_replies_enabled = true
    ::HackerNewsClient::CategorySeeder.ensure_category!
  end

  let(:story_hn_id) { 9_000_001 }

  def import_story_with_one_comment
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/#{story_hn_id}.json").to_return(
      status: 200,
      body: {
        "id" => story_hn_id,
        "type" => "story",
        "by" => "dang",
        "title" => "S",
        "url" => "https://e.example",
        "time" => 1_600_000_000,
        "kids" => [201],
      }.to_json,
    )
    stub_request(:get, "https://hn.algolia.com/api/v1/items/#{story_hn_id}").to_return(
      status: 200,
      body: {
        "id" => story_hn_id,
        "children" => [
          {
            "id" => 201,
            "author" => "alice",
            "text" => "original",
            "created_at_i" => 1_600_000_100,
            "children" => [],
          },
        ],
      }.to_json,
    )
    ::HackerNewsClient::StoryImporter.new(story_hn_id).import!
  end

  it "revises an existing comment when the Firebase text differs" do
    import_story_with_one_comment

    updated_item = {
      "id" => 201,
      "type" => "comment",
      "by" => "alice",
      "parent" => story_hn_id,
      "text" => "<p>updated body</p>",
      "time" => 1_600_000_100,
    }

    described_class.new(updated_item).sync!

    post = ::HackerNewsClient::Lookup.post_for(201)
    expect(post.raw).to include("updated body")
    expect(post.edit_reason).to eq(I18n.t("hacker_news_client.edit_reason"))
  end

  it "soft-deletes a post when the item is marked dead" do
    import_story_with_one_comment

    dead_item = { "id" => 201, "type" => "comment", "dead" => true }
    described_class.new(dead_item).sync!

    post =
      Post
        .with_deleted
        .joins(:_custom_fields)
        .find_by(post_custom_fields: { name: "hn_id", value: "201" })
    expect(post.trashed?).to eq(true)
  end

  it "does not revise a trashed post when the item is live" do
    import_story_with_one_comment
    post = ::HackerNewsClient::Lookup.post_for(201)
    PostDestroyer.new(Discourse.system_user, post, context: "test").destroy

    live_item = {
      "id" => 201,
      "type" => "comment",
      "by" => "alice",
      "parent" => story_hn_id,
      "text" => "<p>updated body</p>",
      "time" => 1_600_000_100,
      "kids" => [202],
    }

    expect { described_class.new(live_item).sync! }.not_to change {
      Jobs::HackerNewsClient::SyncItem.jobs.length
    }
    expect(::HackerNewsClient::Lookup.post_for(201).raw).to include("original")
  end

  it "creates a new comment under the resolved parent" do
    import_story_with_one_comment

    stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/201.json").to_return(
      status: 200,
      body: { "id" => 201, "kids" => [202] }.to_json,
    )

    new_item = {
      "id" => 202,
      "type" => "comment",
      "by" => "bob",
      "parent" => 201,
      "text" => "<p>fresh reply</p>",
      "time" => 1_600_000_200,
    }

    expect { described_class.new(new_item).sync! }.to change { Post.count }.by(1)

    new_post = ::HackerNewsClient::Lookup.post_for(202)
    parent_post = ::HackerNewsClient::Lookup.post_for(201)
    expect(new_post.reply_to_post_number).to eq(parent_post.post_number)
    expect(new_post.raw).to include("fresh reply")
    expect(Jobs::ProcessPost.jobs.map { |j| j["args"].first["post_id"] }).to include(new_post.id)
  end

  it "rechecks for an existing post inside the creation mutex" do
    import_story_with_one_comment

    existing_post = Fabricate(:post)
    existing_post.custom_fields["hn_id"] = "202"
    existing_post.save_custom_fields

    allow(::HackerNewsClient::Lookup).to receive(:post_for).and_call_original
    allow(::HackerNewsClient::Lookup).to receive(:post_for).with(202).and_return(
      nil,
      nil,
      existing_post,
    )

    new_item = {
      "id" => 202,
      "type" => "comment",
      "by" => "bob",
      "parent" => 201,
      "text" => "<p>fresh reply</p>",
      "time" => 1_600_000_200,
    }

    expect { described_class.new(new_item).sync! }.not_to change { Post.count }
  end

  it "does not create a new comment when the parent rank cannot be resolved" do
    import_story_with_one_comment

    stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/201.json").to_return(
      status: 404,
      body: "",
    )

    new_item = {
      "id" => 202,
      "type" => "comment",
      "by" => "bob",
      "parent" => 201,
      "text" => "<p>fresh reply</p>",
      "time" => 1_600_000_200,
    }

    expect { described_class.new(new_item).sync! }.not_to change { Post.count }
  end

  it "does not create a new comment under a trashed parent" do
    import_story_with_one_comment
    parent_post = ::HackerNewsClient::Lookup.post_for(201)
    PostDestroyer.new(Discourse.system_user, parent_post, context: "test").destroy

    new_item = {
      "id" => 202,
      "type" => "comment",
      "by" => "bob",
      "parent" => 201,
      "text" => "<p>fresh reply</p>",
      "time" => 1_600_000_200,
    }

    expect { described_class.new(new_item).sync! }.not_to change { Post.count }
  end
end
