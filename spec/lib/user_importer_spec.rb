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
end
