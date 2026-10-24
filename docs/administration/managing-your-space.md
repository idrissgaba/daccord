---
title: Managing Your Space
description: Configure channels, roles, and settings for your space.
order: 1
section: administration
---

# Managing Your Space

If you have admin permissions, you can manage your space's channels, roles, and settings.

## Accessing Space Settings

Right-click a space icon in the space bar and select **Space Settings** (or the equivalent admin option) to open the management panel.

## Icon and Banner

Upload an icon in **Overview**, apply the crop, then choose **Save settings**.
The pending preview shows the selected crop immediately. Icons are exported as
PNG up to 512 pixels; banners use a 16:9 crop up to 1024 pixels wide. Banner
changes and removal save immediately, with **Save settings** available to retry
an unsuccessful change. Saved replacements refresh the settings preview and
space bar during the same session, even when the server reuses the image URL.

## Channels

### Creating a Channel

1. In space settings, go to the Channels section.
2. Click **Create Channel**.
3. Choose a channel type (text, voice, announcement, or forum).
4. Enter a name and optionally assign it to a category.
5. Click **Create**.

### Editing a Channel

Click on a channel in the settings list to edit its name, topic, or other properties.

### Deleting a Channel

Select a channel and click **Delete**. This permanently removes the channel and all its messages.

### Categories

Channels can be organized into categories. Create, rename, or delete categories from the Channels section.

## Roles

Roles control what members can do in your space.

### Creating a Role

1. Go to the Roles section in space settings.
2. Click **Create Role**.
3. Set a name and color.
4. Toggle individual permissions on or off.
5. Save the role.

### Assigning Roles

Right-click a member in the member list and select a role to assign or remove.

### Channel Permissions

You can set per-channel permission overrides for specific roles:

1. Open the channel's settings.
2. Go to Permissions.
3. Add a role and set permissions to **Allow**, **Inherit**, or **Deny** for each permission.

## Welcome Screen

Open **Welcome screen** in space settings (needs Manage Space) to greet members
the first time they open the space. Write a short description and recommend up
to five channels, each with an emoji and a reason to go there. Turn on **Show
to new members** to enable it. Each member sees it once; tapping a recommended
channel opens it.

## Invites

See [Invites](invites.md) for details on inviting people to your server.

## Arcade

Open **Arcade** in space settings to enable reviewed games and manage the
space's Arcade. See [Managing Arcade](managing-arcade.md) for channel placement,
notifications, idle cleanup, and custom extensions.

## Webhooks

A webhook lets another service post into a text channel — monitoring alerts,
download notifications, build results. In **Space Settings → Webhooks** (you
need the Manage Webhooks permission):

1. Click **New webhook** and pick the channel it posts in.
2. Click the link icon to copy its URL, and paste it into the service's
   notification settings (services that support chat webhooks accept it as is).
3. From the **⋮** menu you can rename it, move it to another channel, change its
   avatar, or delete it.

Keep the URL secret: anyone who has it can post in that channel. Deleting the
webhook stops the URL working; what it already posted stays. Messages from a
webhook (or a bot) show an **APP** badge next to the name. A webhook can't
notify `@everyone` unless the service explicitly asks to.

## Events

Plan things for the space — a movie night in a voice channel, a meetup
somewhere else. The **Events** row at the top of the channel list shows how
many are coming up, and turns red with **LIVE** while one is under way.

- **Create event** (needs the Manage Events permission): pick a voice channel or
  type a location, a name, a description, when it starts and (required for an
  event somewhere else) when it ends, and optionally a cover image.
- Anyone can click **Interested** — on the desktop app you get a notification
  when it starts. **Add to calendar** saves a `.ics` file for your calendar app.
- Events start on their own at their start time and end at their end time (or
  12 hours later if they have none). Managers can also **Start now**, **End
  event**, **Edit**, **Cancel event** or **Delete** from the event's menu.
- While a voice event is live, **Join** puts you in its channel.
