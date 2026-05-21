# frozen_string_literal: true

module ::HackerNewsClient
  class AlgoliaClient
    BASE_URL = "https://hn.algolia.com/api/v1"
    USER_AGENT = "Discourse hacker-news-client/0.1"
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    def item_tree(id)
      get_json("#{BASE_URL}/items/#{id}")
    end

    private

    def get_json(url)
      body = fetch(url)
      return nil if body.nil?

      JSON.parse(body)
    rescue JSON::ParserError => e
      Rails.logger.warn("HackerNewsClient: invalid JSON from #{url}: #{e.message}")
      nil
    end

    def fetch(url, retries_left: 1)
      uri = URI.parse(url)
      request = FinalDestination::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/json"

      response =
        FinalDestination::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT,
        ) { |http| http.request(request) }

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPNotFound
        nil
      when Net::HTTPServerError
        if retries_left > 0
          sleep 1
          fetch(url, retries_left: retries_left - 1)
        else
          Rails.logger.warn("HackerNewsClient: #{response.code} from #{url}")
          nil
        end
      else
        Rails.logger.warn("HackerNewsClient: #{response.code} from #{url}")
        nil
      end
    rescue StandardError => e
      Rails.logger.warn("HackerNewsClient: error fetching #{url}: #{e.message}")
      nil
    end
  end
end
