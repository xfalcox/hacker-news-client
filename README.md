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

When a story has a link, `ImportStory` enqueues `Jobs::HackerNewsClient::FetchArticle`,
which fetches the linked article via `TopicEmbed.find_remote` (ruby-readability
extraction, with core's SSRF protection) and caches the extracted text in a
`TopicEmbed` row tied to the topic. discourse-ai reads
`topic.topic_embed.embed_content_cache` when building embeddings and summaries, so
this feeds those features the full article rather than just the HN title and
comments. Gated by `hacker_news_client_fetch_articles` (default on); Ask HN / text
posts are skipped.

## Topic ordering on /hot

Every minute, `RefreshTopStories` writes `topic_hot_scores.score` from the
HN-ranked position (rank 0 ≈ `BASE_SCORE`, rank N ≈ `BASE_SCORE - N`). The
base is well above what Discourse's natural algorithm produces (~0–100), so
HN-ranked topics always dominate `/hot` and appear in exact HN order. A
listener on `:topic_hot_scores_updated` re-applies the scores immediately
after Discourse's scheduled `UpdateTopicHotScores` job overwrites them every
10 minutes. Topics that fall off the current HN top list are zeroed back out
so they don't linger on `/hot`. This assumes the instance is an HN-mirror;
on a multi-purpose forum the mass score-overwrite would crowd out organic
content.

## Comment ordering

The plugin registers an `hn_rank` algorithm on `NestedReplies::Sort` (using the
`hn_rank` post custom field set at import time) and adds `"hn_rank"` to the
choices for the core `nested_replies_default_sort` site setting. When the
plugin first activates it also flips that setting from Discourse's out-of-the-
box `"top"` to `"hn_rank"` so clicking through to an HN topic sorts by HN rank
by default — an admin who has set a different value is left alone. Topics in
other nested-replies categories without an `hn_rank` custom field sort by
`post_number ASC` under this default, which is equivalent to the `"old"`
algorithm. Users can still pick `top`/`new`/`old` from the sort dropdown
manually.

## Settings

- `hacker_news_client_enabled` — master switch.
- `hacker_news_client_top_stories_count` — how many front-page ids to mirror (default 30).
- `hacker_news_client_fetch_articles` — fetch each linked article and cache its text on
  the topic embed for better AI embeddings/summaries (default on).

## Requirements

- `SiteSetting.nested_replies_enabled` must be on for the imported topics to render in
  nested view; otherwise they fall back to flat view.
- `SiteSetting.topic_featured_link_enabled` should be on (default) for story link cards
  to render on topic lists.

The plugin logs a one-time warning if either prerequisite is off when the plugin enables.
It does not flip core site settings on the user's behalf.
