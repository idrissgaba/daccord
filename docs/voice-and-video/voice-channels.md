---
title: Voice and Video
description: Join voice channels for real-time audio and video conversations.
order: 1
section: voice-and-video
---

# Voice and Video

Voice channels let you talk to other people in real time using your microphone, camera, or screen share.

## Joining a Voice Channel

1. In the channel list, click a **voice channel** (marked with a speaker icon).
2. daccord connects you to the voice room.
3. A **voice bar** appears at the bottom of the channel panel showing the channel name, a green status dot, and control buttons.

Other participants in the channel are shown with their avatar, display name, and status indicators (muted, deafened, camera on, sharing screen).

## Voice Controls

The voice bar provides these controls:

- **Mute** -- Toggle your microphone on/off
- **Deafen** -- Mute all incoming audio (also mutes your mic)
- **Camera** -- Toggle your camera on/off
- **Screen Share** -- Share your screen or a specific window
- **Soundboard** -- Play audio clips into the channel
- **Settings** -- Open voice settings
- **Disconnect** -- Leave the voice channel

If a moderator mutes or deafens you, the microphone (or headset) button turns
red and says so when you hover it; your own mute still works, and your
microphone comes back on its own when they lift it. If a moderator moves you
to another channel, the app follows you there.

## Speaking Indicator

When someone is speaking, a green ring appears around their avatar in the participant list.

## User Volume

Right-click (desktop and web) or long-press (mobile) another participant — in the
channel list or on their tile in the voice view — to open **User Volume**:

- **User Volume** -- how loud that person (or bot) sounds to you, 0–200 %. It
  multiplies the global output volume from Voice & Video settings.
- **Mute for me** -- silences them for you only; unmuting restores your volume.
- **Reset** -- back to 100 % and unmuted.

These settings are local: nobody else hears a difference. They are saved per
server and per user ID, and apply immediately, on rejoin and after reconnecting.
On the web the browser cannot amplify remote audio, so the slider stops at 100 %.

## Screen Sharing

1. Click the **Screen Share** button in the voice bar.
2. Choose which screen or window to share from the picker.
3. Your screen share appears as a video tile for other participants.
4. Click the button again to stop sharing.

## Video

Click the **Camera** button to share your camera feed. Other participants see your video as a tile in the voice channel view.

## Voice Settings

Access voice and video settings from the voice bar settings button or from **App Settings > Voice & Video**. Here you can configure your input/output devices and other audio preferences.

The **Output device** picker is shown on desktop and Android, where the platform can honour an explicit choice. iOS routes call audio itself — use Control Centre, the AirPlay picker, or plug in a headset — so the app does not offer a picker that iOS would ignore.

### Relay-only connections

Enable **Relay-only voice** in **Voice & Video** settings to require a TURN relay
for voice, video and screen sharing. Leave and rejoin to apply it to a current
call. The option is off by default, can add latency, and requires the server's
LiveKit deployment to provide reachable TURN. Failed relay connections report an
error and do not fall back to direct media. See [network privacy](../privacy-network.md).

## Stage Channels

A **Stage** (create it like any channel, type **Stage**) is a voice channel
with an audience, for talks, shows and Q&As.

- Everyone joins in the **audience**: you can listen, but your microphone,
  camera and screen share are off.
- Press the **hand** button to ask to speak; press it again to lower your hand.
- Stage moderators (members who can **Mute Members**) see raised hands first
  in the audience list and press **Invite** to bring someone up. From a
  speaker's menu they can **Move to Audience**; they can also step up
  themselves with **Speak on stage**.
- A speaker leaves the stage with **Move to audience**. Rejoining the channel
  always starts in the audience.
