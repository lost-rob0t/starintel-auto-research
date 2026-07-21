---
name: "social-actor"
description: "Build a Starintel social-platform collector using User, Message, and SocialMediaPost documents."
version: "1.1.0"
author: "lost-rob0t"
category: "collection"
tags: ["starintel", "collection", "social-actor", "osint"]
---

# Social Actor

## Objective

Collect platform accounts, posts, messages, replies, mentions, links, and media into Starintel while preserving platform identifiers, collection provenance, pagination state, edits, and rate-limit behavior.

## Procedure

1. Define the platform, actor name, supported target forms, required account or API configuration, dataset restrictions, collection modes, and explicit output types.
2. Accept a validated Starintel target and register the actor name used by that target. Keep credentials and session tokens outside the target document.
3. Preserve platform-native identifiers and URLs before normalization.
4. Map records to the current schema:
   - account or profile to `User` with `url`, `name`, `platform`, `bio`, and `misc`;
   - chat or channel item to `Message` with content, platform, user, message ID, reply, group, channel, mentions, and media;
   - public post to `SocialMediaPost` with content, user, URL, replies, media, counts, links, tags, title, group, and reply target.
5. Use canonical constructors and deterministic IDs where defined. Preserve the same assigned ID across retries.
6. Create directed relations such as `account-of`, `mentions`, `replies-to`, `links-to`, `member-of`, or `extracted-from` only when the evidence supports the direction and predicate.
7. Record source URL or API record reference in `sources` and preserve raw responses or export artifacts for replay.
8. Keep cursor, page, since-ID, or checkpoint state outside immutable evidence and persist it before acknowledging progress.
9. Respect platform rate-limit responses with bounded backoff and actor events. Do not convert rate limits into tight retry loops.
10. Represent edits, deletions, and changed metrics explicitly as new observations, revisions, or events according to the active design. Do not silently erase the prior collected state.
11. Separate collection from identity resolution. Similar usernames, names, avatars, or bios are leads, not proof that accounts belong to the same person.
12. Emit canonical documents through the normal Rabbit ingest route and send invalid records to the rejection/dead-letter path with platform context.
13. Test pagination, resume, duplicate records, replies, mentions, media, deleted content, edited content, rate limits, auth expiry, account suspension, and partial API failure.

## Exit Criteria

- Platform IDs, URLs, source references, and raw evidence are preserved.
- Output documents match the cross-language schema fixtures.
- Resume and retry are bounded and idempotent.
- Identity claims remain separate from observed account data.
- Collection lifecycle and failures are visible through actor events.
