---
title: File Sharing
description: Share images and files in conversations.
order: 4
section: messaging
---

# File Sharing

You can share files and images directly in any text channel or DM.

## Uploading Files

Attach a file to your message using the attachment button in the composer, or drag files from your file manager and drop them onto the composer.

The maximum file size is **25 MB** per file. Larger files are rejected as soon as you pick them, with the file's size shown next to the limit -- nothing is uploaded. Music and video files are the ones that most often run into this; a 320 kbps MP3 passes 25 MB at around ten minutes.

If the server refuses an upload for another reason -- you don't have the **Attach Files** permission in that channel, for example -- the reason it gives is shown above the composer.

## Pasting Images

Copy an image to your clipboard and paste it directly into the composer with **Ctrl+V** (or **Cmd+V** on macOS). This works with screenshots and images copied from other apps.

You can also paste large blocks of text -- they'll be attached as a text file rather than sent as an enormous message.

## Viewing Attachments

- **Images** are displayed inline within the message. Click an image to view it at full size.
- **Audio files** show an inline player with a progress slider so you can listen without downloading.
- **Video files** show a clickable thumbnail. Click it to play the video.
- **Other files** appear as a download link with the filename.

## Voice Messages

With nothing typed or attached, the composer's send button becomes a
**microphone**. Click it to start recording: a red dot, a timer and a live level
bar replace the text field. Click **Send** to send the recording, or the bin to
discard it. Recordings shorter than a second are discarded, and recording stops
and sends on its own after ten minutes.

A voice message is an ordinary audio attachment (AAC/MP4 where the platform can
record it, Opus/WebM in Firefox), so every client can play it; this client labels
it "Voice message" with a microphone icon. Like any upload, it counts against
the server's upload limits and is held back while an upload cooldown runs.
