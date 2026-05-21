# frozen_string_literal: true

RSpec.describe ::HackerNewsClient::CategorySeeder do
  describe ".ensure_category!" do
    it "creates the Hacker News category on first call and reuses it after" do
      expect { described_class.ensure_category! }.to change { Category.count }.by(1)

      category = described_class.ensure_category!
      expect(category.slug).to eq("hacker-news")
      expect(category.color).to eq("FF6600")
      expect(category.nested_replies_default).to eq(true)
      expect(category.topic_featured_link_allowed).to eq(true)

      expect { described_class.ensure_category! }.not_to change { Category.count }
    end

    it "re-uses an existing category referenced by the plugin store" do
      existing =
        Fabricate(
          :category,
          name: "Hacker News",
          slug: "hacker-news",
          nested_replies_default: true,
          topic_featured_link_allowed: true,
        )
      PluginStore.set(::HackerNewsClient::PLUGIN_NAME, "category_id", existing.id)

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(described_class.ensure_category!).to eq(existing)
    end

    it "repairs required settings on an existing category" do
      existing =
        Fabricate(
          :category,
          name: "Hacker News",
          slug: "hacker-news",
          nested_replies_default: false,
          topic_featured_link_allowed: false,
        )
      PluginStore.set(::HackerNewsClient::PLUGIN_NAME, "category_id", existing.id)

      described_class.ensure_category!

      existing.reload
      expect(existing.nested_replies_default).to eq(true)
      expect(existing.topic_featured_link_allowed).to eq(true)
    end

    describe "nested_replies_default_sort" do
      it "flips the global default to hn_rank when it's still at Discourse's default" do
        SiteSetting.nested_replies_default_sort = "top"
        described_class.ensure_category!
        expect(SiteSetting.nested_replies_default_sort).to eq("hn_rank")
      end

      it "leaves the global default alone when an admin has set something else" do
        SiteSetting.nested_replies_default_sort = "new"
        described_class.ensure_category!
        expect(SiteSetting.nested_replies_default_sort).to eq("new")
      end
    end
  end
end
