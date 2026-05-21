# frozen_string_literal: true

module ::HackerNewsClient
  module CategorySeeder
    PLUGIN_STORE_KEY = "category_id"

    module_function

    def category_id
      ensure_category!&.id
    end

    def ensure_category!
      id = PluginStore.get(::HackerNewsClient::PLUGIN_NAME, PLUGIN_STORE_KEY)
      category = Category.find_by(id: id) if id

      unless category
        category = Category.find_by(slug: I18n.t("hacker_news_client.category.slug"))
        PluginStore.set(::HackerNewsClient::PLUGIN_NAME, PLUGIN_STORE_KEY, category.id) if category
      end

      category ||= create_category!
      ensure_category_configuration!(category)
      ensure_default_sort!

      warn_if_nested_view_disabled
      warn_if_featured_link_disabled

      category
    end

    def create_category!
      category =
        Category.create!(
          name: I18n.t("hacker_news_client.category.name"),
          slug: I18n.t("hacker_news_client.category.slug"),
          description: I18n.t("hacker_news_client.category.description"),
          color: "FF6600",
          text_color: "FFFFFF",
          user: Discourse.system_user,
          topic_featured_link_allowed: true,
        )
      category.category_setting.update!(nested_replies_default: true)
      PluginStore.set(::HackerNewsClient::PLUGIN_NAME, PLUGIN_STORE_KEY, category.id)
      category
    end

    def ensure_category_configuration!(category)
      unless category.topic_featured_link_allowed
        category.update!(topic_featured_link_allowed: true)
      end

      unless category.category_setting.nested_replies_default
        category.category_setting.update!(nested_replies_default: true)
      end
    end

    # Only flip the global default if it's still at Discourse's out-of-the-box
    # value, so we don't override an admin who deliberately picked something
    # else. Non-HN nested topics under `hn_rank` fall back to post_number ASC
    # (equivalent to "old" sort), which is the natural tree order.
    def ensure_default_sort!
      return unless SiteSetting.nested_replies_default_sort == "top"
      SiteSetting.nested_replies_default_sort = ::HackerNewsClient::Sort::HN_RANK
    end

    def warn_if_nested_view_disabled
      return if SiteSetting.nested_replies_enabled || @warned_nested_view_disabled

      @warned_nested_view_disabled = true
      Rails.logger.warn(
        "HackerNewsClient: nested_replies_enabled is off — imported topics will render in flat view.",
      )
    end

    def warn_if_featured_link_disabled
      return if SiteSetting.topic_featured_link_enabled || @warned_featured_link_disabled

      @warned_featured_link_disabled = true
      Rails.logger.warn(
        "HackerNewsClient: topic_featured_link_enabled is off — story link cards will not render.",
      )
    end
  end
end
