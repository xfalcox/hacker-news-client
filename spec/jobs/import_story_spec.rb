# frozen_string_literal: true

RSpec.describe ::Jobs::HackerNewsClient::ImportStory do
  before { SiteSetting.hacker_news_client_enabled = true }

  it "delegates to the importer so retries can repair partial imports" do
    importer = instance_spy(::HackerNewsClient::StoryImporter)
    allow(::HackerNewsClient::StoryImporter).to receive(:new).with(123).and_return(importer)

    described_class.new.execute(hn_id: 123)

    expect(importer).to have_received(:import!)
  end
end
