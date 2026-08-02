# Azaman Core Features Reference

This document outlines the essential implementation details of the Azaman platform's core features. It is intended to serve as a reference point for future development and maintainers.

## 1. Premium Chat Architecture

### Real-Time Delivery & Fallback
Azaman implements a highly resilient chat delivery system that prioritizes speed and reliability, mirroring the best practices of modern messengers.

- **WebSocket First**: Messages are primarily sent and received via `SocketService`. This ensures instantaneous delivery under normal network conditions.
- **REST API Fallback (`premium_chat_provider.dart`)**: If the WebSocket fails to acknowledge a message within 5 seconds, the app automatically falls back to the REST API (`apiClient.post`) to guarantee delivery.
- **Local Optimistic Updates**: When a user sends a message, it is immediately rendered in the UI with a "sending" state. Only upon acknowledgment (via socket or REST) does the state flip to "sent" (one tick) or "delivered" (two ticks).
- **Idempotency**: All messages utilize a UUID `nonce`. The backend uses this nonce to deduplicate messages, ensuring that a slow socket and a subsequent REST retry don't result in duplicate messages.

## 2. Audio Recorder UI (Telegram-style)

The audio recording experience mimics Telegram closely, featuring a "slide-to-cancel" interaction model.

- **Implementation (`audio_recorder_button.dart`)**: 
  - Uses a `GestureDetector` to track drag updates (`onPanUpdate`). 
  - As the user slides left, `Transform.translate` visually moves the microphone icon.
  - If the drag distance exceeds a threshold (`_cancelThreshold`), the recording is aborted.
- **UI Constraints**: To prevent overflow errors on smaller screens (the "yellow-black tape" banner), the recording UI strip is wrapped in `BoxConstraints` and `AnimatedContainer`, ensuring the sliding animations are bounded strictly within the screen width.

## 3. Stories and Statuses

The "Statuses" feed utilizes a tiered visibility system:

- **Frontend (`story_provider.dart`)**: 
  - Statuses are grouped by author. 
  - A "My Status" entry is always prepended to the story feed in `messages_hub_screen.dart`, even when no other friends have posted stories. Tapping this triggers the native `ImagePicker` and opens `StoryCreationScreen`.
  - The `StoryRing` widget dynamically changes its gradient and thickness based on whether the stories are unseen or if the user has boosted their visibility.
- **Backend (`storyService.js`)**: 
  - Pulls active stories from the user's friend list (`friendIds`).
  - Implements a sophisticated sorting algorithm (`peerStoriesComparator`): 
    1. The user's own stories (if any).
    2. Friends with *unseen* stories.
    3. Friends with *boosted* stories.
    4. Chronological order (latest first).

## 4. Backend Synchronization & Deployment

- **Hosting**: The Azaman backend is designed to be deployed to Render. 
- **Continuous Integration**: The `AZM-backend-main` repository is linked to the deployment pipeline. Pushing changes to the `main` branch automatically triggers a rebuild and redeployment on the live server.
- **Media**: Stories and profile pictures are uploaded via `multer` directly to Cloudinary (`cloudinaryService.js`).
