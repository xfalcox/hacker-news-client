# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::UserImporter do
  describe ".find_or_create_for_hn" do
    it "creates a staged user with the HN username preserved" do
      expect { described_class.find_or_create_for_hn("dang") }.to change { User.count }.by(1)

      user = ::HackerNewsClient::Lookup.user_for_hn_username("dang")
      expect(user).to be_present
      expect(user).to be_staged
      expect(user.email).to eq("dang@hn.invalid")
      expect(user.custom_fields["hn_username"]).to eq("dang")
    end

    it "is idempotent for the same HN username" do
      first = described_class.find_or_create_for_hn("pg")
      second = described_class.find_or_create_for_hn("pg")
      expect(first).to eq(second)
    end

    it "rechecks for an existing user inside the creation mutex" do
      existing = Fabricate(:user)
      allow(::HackerNewsClient::Lookup).to receive(:user_for_hn_username).with("pg").and_return(
        nil,
        existing,
      )

      expect(described_class.find_or_create_for_hn("pg")).to eq(existing)
    end

    it "handles HN usernames that collide with existing Discourse usernames" do
      Fabricate(:user, username: "dang")
      hn_user = described_class.find_or_create_for_hn("dang")
      expect(hn_user.username).not_to eq("dang")
      expect(hn_user.custom_fields["hn_username"]).to eq("dang")
    end
  end

  describe ".voter_pool" do
    before { SiteSetting.hacker_news_client_voter_pool_size = 3 }

    it "creates and reuses staged voter accounts" do
      expect { described_class.voter_pool }.to change { User.count }.by(3)
      expect { described_class.voter_pool }.not_to change { User.count }

      pool = described_class.voter_pool
      expect(pool.length).to eq(3)
      expect(pool.first.custom_fields["hn_username"]).to eq("hn_voter_001")
    end
  end
end
