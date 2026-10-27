# Chat history summary (debug prototype)

Internal-only prototype: long-press a chat in the **chat list** → **Chat Summary**. Loads the
last N recent messages (read or unread), asks a provider for a structured summary, and shows it in
a sheet. Production logic is expected to move to the backend later; the client keeps
`ChatHistorySummaryProviding` as the seam.

## Entry points

| Piece | Where |
| --- | --- |
| Menu gate + provider wiring | `submodules/ChatListUI/Sources/ChatContextMenus.swift` (`canDisplayMockChatHistorySummary`, `ChatHistorySummaryScreen`) |
| Model / mock / state machine | `submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatHistorySummary.swift` |
| OpenAI-compatible LLM provider | `submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatHistorySummaryLLM.swift` |
| Sheet UI | `submodules/TelegramUI/Components/Chat/ChatHistorySummaryScreen/` |
| Debug knobs | `ExperimentalUISettings` + `DebugController` |

The menu item is shown only when **all** of these hold:

1. Internal app build (`appBuildType == .internal`)
2. Debug Settings ▸ **Chat: history summary (debug)** is on
3. Source is the chat list (not archive/community promo surfaces that fail the gate)
4. Chat is not community / promo

It is **not** gated on unread. Opening a chat clears the badge, so an unread-only gate hid the
action when a summary was most useful. The provider always takes the last `messageLimit` messages.

## Debug Settings

Settings → Debug (internal builds) → scroll to:

| Row | Setting | Default | Notes |
| --- | --- | --- | --- |
| **Chat: history summary (debug)** | `mockChatHistorySummary` | off | Master switch. When on, the extra fields below appear. |
| **Summary URL** | `chatHistorySummaryBaseURL` | `https://openrouter.ai/api/v1` | OpenAI-compatible base. Client appends `/chat/completions` if missing. |
| **Summary Key** | `chatHistorySummaryApiKey` | empty | Bearer token. **Empty key → mock provider** (fixed Russian fixture, ~0.45 s delay). Non-empty → real HTTP call. |
| **Summary Model** | `chatHistorySummaryModel` | `openrouter/free` | Passed as `model` in the chat-completions body. |
| **Summary Max Msgs** | `chatHistorySummaryMaxMessages` | `30` | Clamped 1…100. How many recent transcript lines to load / send. |

No app restart is required after toggling; reopen the chat-list context menu to pick up the gate.

## How to test

### Mock (no network)

1. Internal build on simulator/device.
2. Turn on **Chat: history summary (debug)**.
3. Leave **Summary Key** empty.
4. Long-press any ordinary chat in the chat list → **Chat Summary**.
5. Expect sparkles + shimmer loading, then Overview / Key Points / Decisions / Action Items /
   Suggested Replies from the mock fixture.

### Live LLM (OpenRouter or other OpenAI-compatible host)

1. Same as above, then fill:
   - **Summary URL** — e.g. `https://openrouter.ai/api/v1`
   - **Summary Key** — API key
   - **Summary Model** — a model the host accepts (free tier models vary; failures surface as the
     sheet error + Retry)
   - **Summary Max Msgs** — start with `30`
2. Prefer a chat with recent text messages (media-only lines become `[photo]` / `[file]` stubs;
   service actions are skipped).
3. Long-press → **Chat Summary**. Loading can take tens of seconds on slow models.

### Sheet interactions

- Tap Overview / a bullet / an action row → context menu **Copy**; if the model cited a message,
  also **View in Chat** (opens that message and dismisses the sheet).
- Tap a **Suggested Reply** → dismiss sheet, open the chat, insert the phrase into the composer
  (`updateTextInputState` + `activateInput: .text`). Does not auto-send.
- Action Items are a visual checklist only (no local check state).

## Provider contract

JSON (no markdown fences), language matching the transcript:

```json
{
  "overview": "…",
  "keyPoints": [{"text": "…", "citationMessageId": 123}],
  "decisions": [{"text": "…"}],
  "actionItems": [{"text": "…"}],
  "suggestedReplies": ["…", "…"]
}
```

- Bullet arrays also accept plain strings.
- `citationMessageId` must be one of the `[id]` values from the transcript; unknown ids are dropped.
- Caps: 6 items per list, 3 suggested replies (≤120 chars each).

## Out of scope (for now)

- App Store / non-internal builds
- Server-side summarization (planned; keep `ChatHistorySummaryProviding`)
- Persisted action checkboxes, auto-send of suggested replies
- Committing API keys or local Make.py / provisioning hacks
