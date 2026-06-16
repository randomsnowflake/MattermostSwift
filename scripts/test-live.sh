#!/bin/sh
set -eu

swift run MattermostSwiftCLI check
swift run MattermostSwiftCLI server-info
swift run MattermostSwiftCLI list-teams >/dev/null
swift run MattermostSwiftCLI team-info >/dev/null
swift run MattermostSwiftCLI list-team-members >/dev/null
current_user="$(swift run MattermostSwiftCLI me)"
swift run MattermostSwiftCLI get-user >/dev/null
current_user_id="$(printf "%s\n" "$current_user" | awk '/^id:/ {print $2; exit}')"
current_username="$(printf "%s\n" "$current_user" | awk '/^username:/ {print $2; exit}')"
if [ -z "$current_user_id" ] || [ -z "$current_username" ]; then
    echo "Could not resolve current user id/username." >&2
    exit 1
fi
swift run MattermostSwiftCLI get-users "$current_user_id" >/dev/null
swift run MattermostSwiftCLI profile-image >/dev/null
swift run MattermostSwiftCLI default-profile-image >/dev/null
swift run MattermostSwiftCLI status >/dev/null
swift run MattermostSwiftCLI search-users "$current_username" >/dev/null
swift run MattermostSwiftCLI autocomplete-users "$current_username" >/dev/null
swift run MattermostSwiftCLI known-users >/dev/null
swift run MattermostSwiftCLI known-users --profiles >/dev/null
swift run MattermostSwiftCLI get-users-by-username "$current_username" >/dev/null
swift run MattermostSwiftCLI list-channels >/dev/null
swift run MattermostSwiftCLI list-public-channels >/dev/null
channel_info="$(swift run MattermostSwiftCLI channel-info)"
current_channel_team_id="$(printf "%s\n" "$channel_info" | awk '/^team:/ {print $2; exit}')"
current_channel_name="$(printf "%s\n" "$channel_info" | awk '/^name:/ {print $2; exit}')"
if [ -z "$current_channel_team_id" ] || [ -z "$current_channel_name" ]; then
    echo "Could not resolve current channel team/name." >&2
    exit 1
fi
swift run MattermostSwiftCLI channel-by-name --team "$current_channel_team_id" "$current_channel_name" >/dev/null
if [ -n "${MATTERMOST_TEAM_NAME:-}" ]; then
swift run MattermostSwiftCLI channel-by-team-name "$MATTERMOST_TEAM_NAME" "$current_channel_name" >/dev/null
fi
swift run MattermostSwiftCLI channel-stats >/dev/null
swift run MattermostSwiftCLI channel-timezones >/dev/null
swift run MattermostSwiftCLI channel-member-counts >/dev/null
swift run MattermostSwiftCLI search-channels town >/dev/null
swift run MattermostSwiftCLI search-group-channels "$current_username" >/dev/null
swift run MattermostSwiftCLI channel-member >/dev/null
swift run MattermostSwiftCLI list-channel-members >/dev/null
swift run MattermostSwiftCLI channel-members-by-id "$current_user_id" >/dev/null
swift run MattermostSwiftCLI channel-unread >/dev/null
swift run MattermostSwiftCLI notify-props-test >/dev/null
swift run MattermostSwiftCLI unread-posts-test >/dev/null
swift run MattermostSwiftCLI send-typing >/dev/null
swift run MattermostSwiftCLI list-channel-users >/dev/null
swift run MattermostSwiftCLI list-categories >/dev/null
swift run MattermostSwiftCLI threads-test >/dev/null
swift run MattermostSwiftCLI preferences-test >/dev/null
swift run MattermostSwiftCLI list-posts >/dev/null
swift run MattermostSwiftCLI pinned-posts >/dev/null
swift run MattermostSwiftCLI search mping >/dev/null
swift run MattermostSwiftCLI list-emoji >/dev/null
swift run MattermostSwiftCLI search-emoji a >/dev/null
swift run MattermostSwiftCLI sync >/dev/null
swift run MattermostSwiftCLI all-channel-backfill-test >/dev/null
swift run MattermostSwiftCLI cache-check >/dev/null

if [ -n "${MATTERMOST_USERNAME:-}" ] && [ -n "${MATTERMOST_PASSWORD:-}" ]; then
    swift run MattermostSwiftCLI login-test >/dev/null
fi
