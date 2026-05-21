# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::FirebaseClient do
  subject(:client) { described_class.new }

  describe "#top_stories" do
    it "returns the list of ids" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json").to_return(
        status: 200,
        body: "[1,2,3]",
      )

      expect(client.top_stories).to eq([1, 2, 3])
    end

    it "returns an empty array when the fetch fails" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json").to_return(
        status: 500,
        body: "",
      ).times(2)

      expect(client.top_stories).to eq([])
    end
  end

  describe "#item" do
    it "returns the parsed item" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/42.json").to_return(
        status: 200,
        body: %({"id":42,"type":"story","title":"Hello"}),
      )

      expect(client.item(42)).to eq({ "id" => 42, "type" => "story", "title" => "Hello" })
    end

    it "returns nil on 404" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/42.json").to_return(
        status: 404,
        body: "",
      )

      expect(client.item(42)).to be_nil
    end

    it "returns nil when the body is not JSON" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/42.json").to_return(
        status: 200,
        body: "not json",
      )

      expect(client.item(42)).to be_nil
    end
  end

  describe "#updates" do
    it "returns the parsed payload" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/updates.json").to_return(
        status: 200,
        body: %({"items":[1,2],"profiles":["foo"]}),
      )

      expect(client.updates).to eq({ "items" => [1, 2], "profiles" => ["foo"] })
    end
  end
end
