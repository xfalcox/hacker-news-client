# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::Lookup do
  fab!(:topic)
  fab!(:post)
  fab!(:user)

  before do
    topic.custom_fields["hn_id"] = "42"
    topic.save_custom_fields
    post.custom_fields["hn_id"] = "100"
    post.save_custom_fields
    user.custom_fields["hn_username"] = "pg"
    user.save_custom_fields
  end

  it "finds a topic by hn_id" do
    expect(described_class.topic_for(42)).to eq(topic)
    expect(described_class.topic_for("42")).to eq(topic)
    expect(described_class.topic_for(999)).to be_nil
  end

  it "finds a post by hn_id" do
    expect(described_class.post_for(100)).to eq(post)
    expect(described_class.post_for(999)).to be_nil
  end

  it "finds a trashed post by hn_id" do
    PostDestroyer.new(Discourse.system_user, post, context: "test").destroy

    expect(described_class.post_for(100)).to eq(post)
    expect(described_class.post_for(100, include_trashed: false)).to be_nil
  end

  it "finds a user by hn_username" do
    expect(described_class.user_for_hn_username("pg")).to eq(user)
    expect(described_class.user_for_hn_username("nobody")).to be_nil
  end
end
