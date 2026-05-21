# frozen_string_literal: true

module ::HackerNewsClient
  module NestedTopicsControllerExtension
    private

    def validated_sort
      sort = params[:sort].to_s.downcase
      return sort if ::NestedReplies::Sort.valid?(sort)
      return ::HackerNewsClient::Sort::HN_RANK if @topic&.custom_fields&.[]("hn_id").present?
      super
    end
  end
end
