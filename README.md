# dunst_plusplus

`dunst_plusplus` is a Bash-based notification post-processor for `dunst`.

The intended flow is:

1. A first `dunst` rule catches a notification and suppresses display.
2. That rule calls `runner.sh` with the original notification payload.
3. `runner.sh` normalizes the sender, suppresses duplicates, chooses or builds an icon, applies routing and exclusion rules, and re-sends the notification under a new app name.
4. A second `dunst` rule matches the rewritten app name and displays the final notification with the icon and formatting you want.

This is useful when the original notification source does not provide stable icons, uses inconsistent sender names, or appears through multiple clients at once.

## Features

- Re-sends chat notifications as `visible-chat` or priority-specific app names for a second-stage `dunst` rule.
- Suppresses duplicate notifications within a short time window.
- Applies channel- and keyword-based priority routing for `gomuks` using `dpp.env`.
- Applies global exclusion keywords before re-sending any supported chat app.
- Normalizes North American phone numbers before matching and duplicate checks.
- Displays normalized phone numbers as `(555) 555-1212`.
- Strips trailing ` (#channel-name)` room suffixes from summaries before identifier matching.
- Normalizes gomuks-style image filename bodies like `image.jpg` to `Sent a picture`.
- Supports bootstrap image files in `configstore` and converts them into cached PNG icons.
- Generates deterministic fallback avatars when no configured match exists.

## Requirements

- `bash`
- `notify-send`
- `wget`
- `shasum`
- One of:
  - `magick`
  - `convert`

Optional:

- `dicebear`

## Files

- `runner.sh`: main notification processing script.
- `dpp.env`: channel, keyword, and exclusion routing rules.
- `configstore`: local mapping file used at runtime.
- `configstore.example`: example mapping format.
- `dunstrc.example`: example `dunst` configuration.
- `test_notifications.sh`: emits test notifications for routing and exclusion checks.
- `cache/messages`: duplicate suppression cache, created at runtime.
- `cache/icons`: generated and converted icon cache, created at runtime.

## Usage

```bash
./runner.sh [--loud] appname summary body icon
./runner.sh --help
```

Example:

```bash
./runner.sh gomuks "1-555-010-4242" "hello there" dialog-information
```

## How Matching Works

`runner.sh` tries to resolve `summary` as the sender identifier.

If the identifier is a valid NANP phone number, it is normalized to a 10-digit canonical form for matching and duplicate detection. For display, it is formatted as `(555) 555-1212`.

The lookup order is:

1. Match `field1` in `configstore`.
2. Match any alias listed in `field3`.
3. If no match exists, generate a deterministic fallback avatar from the normalized identifier.

Non-phone identifier matching is case-insensitive. Phone matching is normalized to canonical digits before comparison.

## Config Format

`configstore` uses colon-separated fields:

```text
primary_identifier:value:alias1,alias2,alias3
```

Examples:

```text
alex:/path/to/icons/alex.jpg:alex,alex river
casey:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:casey,casey lane
5550104242:/path/to/contact-photo.jpg:1-555-010-4242,(555) 010-4242
```

Field meanings:

- `field1`: canonical display identifier or primary lookup value.
- `field2`: either a file path to a source image or a previously cached SHA identifier.
- `field3`: optional comma-separated aliases.

If `field2` is a file path, `runner.sh` converts that image to PNG, stores it in `cache/icons/<sha>.png`, and rewrites the config entry to use the SHA on future runs.

## Priority Routing

`runner.sh` reads `dpp.env` from the same directory as the script.

Current keys:

```text
channel_whitelist:#channel-a,#channel-b
channel_yellowlist:#channel-c,#channel-d
channel_redlist:#channel-e,#channel-f
keywords_high:term one,term two
keywords_med:term three
keywords_low:term four,term five
keywords_exclude:exact phrase,another phrase
```

Behavior:

- `keywords_exclude` is checked first for every supported chat app.
- Exclude matching is case-insensitive substring matching.
- For `gomuks`, a trailing ` (#channel-name)` suffix is extracted from the summary and used for channel routing.
- Channel list matches are case-sensitive and assign:
  - `visible-chat-high`
  - `visible-chat-med`
  - `visible-chat-low`
- Keyword matches are case-insensitive substring matches on the body.
- Keyword matches override the channel-derived priority.
- If a `gomuks` notification matches neither a channel tier nor a keyword tier, it is suppressed.
- Non-`gomuks` notifications bypass the channel/keyword priority logic and are sent as plain `visible-chat`, unless excluded first.
- Missing keys in `dpp.env` are treated as unconfigured tiers.

## Duplicate Suppression

Duplicates are tracked in `cache/messages`.

The duplicate key is built from:

- normalized sender display identity
- notification body

This is deliberate so that multiple clients carrying the same underlying message can collapse into one notification even if their raw sender formatting differs.

Because body normalization happens before duplicate checks, `image.jpg` and `Sent a picture` can collapse into the same logical notification after rewrite.

## Dunst Integration

The repository includes [`dunstrc.example`](./dunstrc.example), but the general model is:

1. Add a hidden rule for source applications such as `gomuks`, `cinny`, `beeper`, `equibop`, or `teams-for-linux`.
2. Have that rule call `runner.sh` with the app name, summary, body, and icon.
3. Add visible rules for:
   - `visible-chat`
   - `visible-chat-high`
   - `visible-chat-med`
   - `visible-chat-low`

The hidden rule should suppress the original notification so only the rewritten one is presented.

## Notes

- `runner.sh` currently routes only a fixed set of chat app names through `chat_apps()`: `gomuks`, `cinny`, `beeper`, `equibop`, and `teams-for-linux`.
- The duplicate window is controlled by `HISTORY_TIME` in `runner.sh`.
- If neither online DiceBear nor local `dicebear` is available, fallback avatar generation will fail.

## Testing

Use the included test driver to emit notifications that exercise:

- `gomuks` channel high, medium, and low priority routing
- keyword high, medium, and low routing
- exclusion matches
- non-`gomuks` baseline routing

Preview the commands:

```bash
./test_notifications.sh --dry-run
```

Emit the notifications:

```bash
./test_notifications.sh
```

## Development

Validate shell syntax with:

```bash
bash -n runner.sh
bash -n test_notifications.sh
```
