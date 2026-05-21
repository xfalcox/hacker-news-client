# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::AlgoliaClient do
  subject(:client) { described_class.new }

  describe "#item_tree" do
    it "returns the parsed item tree" do
      stub_request(:get, "https://hn.algolia.com/api/v1/items/42").to_return(
        status: 200,
        body: %({"id":42,"children":[{"id":43,"text":"hello"}]}),
      )

      expect(client.item_tree(42)).to eq(
        { "id" => 42, "children" => [{ "id" => 43, "text" => "hello" }] },
      )
    end

    it "returns nil on 404" do
      stub_request(:get, "https://hn.algolia.com/api/v1/items/42").to_return(status: 404, body: "")

      expect(client.item_tree(42)).to be_nil
    end

    it "returns nil when the body is not JSON" do
      stub_request(:get, "https://hn.algolia.com/api/v1/items/42").to_return(
        status: 200,
        body: "not json",
      )

      expect(client.item_tree(42)).to be_nil
    end
  end
end
