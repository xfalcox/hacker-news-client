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

    # Voter pool ids are stable for the life of a process at a given
    # `hacker_news_client_voter_pool_size`. Memoize to avoid running
    # `voter_pool_size` user lookups on every comment that calls RankLiker.
    def voter_pool
      size = SiteSetting.hacker_news_client_voter_pool_size
      cached = Thread.current[:hn_voter_pool]
      return cached[:users] if cached && cached[:size] == size

      users =
        (1..size).map do |i|
          handle = "hn_voter_#{i.to_s.rjust(3, "0")}"
          find_or_create_for_hn(handle)
        end
      Thread.current[:hn_voter_pool] = { size: size, users: users }
      users
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
