# Hacker News Client

Mirrors the Hacker News front page into a Discourse category to showcase
**Nested Replies mode** with live, realistic data.

- Top 30 front-page stories become topics in a seeded "Hacker News" category.
- HN comments become nested posts under the story topic, preserving the parent-of tree.
- HN authors become staged Discourse users with their HN handle preserved on a user custom field.
- Story URLs are written to `topic.featured_link` (for the link card on topic lists) **and**
  oneboxed inside the topic body.
- Stays in sync as new comments arrive (Firebase `/v0/updates.json` polled every minute).

## How it works

Two scheduled jobs run every minute:

- `Jobs::HackerNewsClient::RefreshTopStories` reads `/v0/topstories.json` and enqueues
  `Jobs::HackerNewsClient::ImportStory` for any id we have not seen before.
- `Jobs::HackerNewsClient::PollUpdates` reads `/v0/updates.json` and enqueues
  `Jobs::HackerNewsClient::SyncItem` for any changed id that we are already tracking
  (or that descends from a tracked item).

`ImportStory` fetches the story from Firebase, fetches the full comment tree from
Algolia (`https://hn.algolia.com/api/v1/items/{id}`), and walks it top-down using each
parent's Firebase `kids` array so sibling order matches HN's ranking.

`SyncItem` resolves a single item to either a new comment (creates one) or an edit
(revises the post). Dead/deleted items soft-destroy their corresponding posts.

## Settings

- `hacker_news_client_enabled` — master switch.
- `hacker_news_client_top_stories_count` — how many front-page ids to mirror (default 30).
- `hacker_news_client_voter_pool_size` — size of the staged voter pool used to mint
  synthetic likes that preserve HN ranking when comments arrive out of order.

## Requirements

- `SiteSetting.nested_replies_enabled` must be on for the imported topics to render in
  nested view; otherwise they fall back to flat view.
- `SiteSetting.topic_featured_link_enabled` should be on (default) for story link cards
  to render on topic lists.

The plugin logs a one-time warning if either prerequisite is off when the plugin enables.
It does not flip core site settings on the user's behalf.
