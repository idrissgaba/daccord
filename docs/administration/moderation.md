---
title: Moderation
description: Keep your community safe with moderation tools.
order: 2
section: administration
---

# Moderation

daccord provides tools for space admins and moderators to manage members and content.

## Member Actions

Right-click a member in the member list to access moderation actions:

- **Kick** -- Remove a member from the space. They can rejoin with a new invite.
- **Ban** -- Permanently remove a member and prevent them from rejoining.
- **Timeout** -- Temporarily restrict a member's ability to send messages.
- **Mute** -- Prevent a member from speaking in voice channels.
- **Deafen** -- Prevent a member from hearing audio in voice channels.

These actions require the appropriate permissions for your role.

## Voice Moderation

Right-click (or long-press) someone in a voice channel to moderate them. You
only see the actions your roles allow:

- **Server Mute** (Mute Members): they can't speak until you lift it, in every
  voice channel of the space.
- **Server Deafen** (Deafen Members): they can neither hear nor speak.
- **Move To** (Move Members): pick another voice channel and they're moved
  there. On a computer you can also drag them onto another voice channel.
- **Disconnect** (Move Members): removes them from voice.

The server enforces these, not the app: a muted member's microphone is cut off
even on another client. Muted and deafened members show a red microphone or
headset icon in the channel list.

A voice channel's **user limit** caps how many people can be in it (shown as
`2/10` next to the channel). Members who can move others can still join a full
channel.

## Managing Bans

1. Open space settings.
2. Go to the **Bans** section.
3. View the list of banned users.
4. Select a user and click **Unban** to allow them to rejoin.

You can unban multiple users at once using bulk selection.

## Reports

Anyone can report a message or an account, and reports are what moderators
act on.

**Filing a report.** Open a message's actions menu (long-press on touch,
right-click or the "..." button on desktop) and choose **Report**, or use
**Report user** on a profile popout or in a direct message's user menu. Pick a
reason, add optional detail, and submit. Reporting is available everywhere
messages are -- inside a space and in direct messages alike.

A reported message is hidden from the reporter's own view straight away, on that
device, whatever the moderators later decide. The report dialog also offers to
**block** the account; outside a space that option is pre-selected, because a
direct message has no moderators and blocking is what actually stops the
contact.

**Where a report goes.** A report filed inside a space goes to that space's
moderators. A report filed outside a space goes to the server operator, on
servers that accept account-level reports; where a server does not, the dialog
says so rather than implying someone will review it, and the block and the local
hide still apply.

**Reviewing reports.** With the `ban_members` permission, open the reports panel
to see what has been filed. Each report can be dismissed, resolved, or actioned
by deleting the reported message, kicking, or banning the account -- resolving a
report from that panel performs the action and closes it in one step.

## Deleting Messages

Admins and moderators can delete any message in channels they have permission to moderate. Right-click the message and select **Delete**.

## Audit Log

The audit log records all administrative actions taken in your space:

1. Open space settings.
2. Go to **Audit Log**.
3. Browse actions by type (kicks, bans, channel changes, role changes, etc.).
4. Use the filter and search to find specific events.

Each entry shows who performed the action, what was affected, and when it happened.
