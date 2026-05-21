# frozen_string_literal: true

module ::HackerNewsClient
  module UserImporter
    module_function

    def find_or_create_for_hn(hn_username)
      Lookup.user_for_hn_username(hn_username) ||
        DistributedMutex.synchronize(
          "hacker_news_client:user:#{hn_username}",
          validity: 5.minutes,
        ) { Lookup.user_for_hn_username(hn_username) || create_staged(hn_username, hn_username) }
    end

    def create_staged(hn_username, name)
      email = "#{hn_username.to_s.downcase}@hn.invalid"
      User.create!(
        email: email,
        username: UserNameSuggester.suggest(hn_username),
        name: name,
        staged: true,
        approved: true,
        trust_level: TrustLevel[0],
        custom_fields: {
          "hn_username" => hn_username,
        },
      )
    end
  end
end
