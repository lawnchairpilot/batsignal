"use strict";
// Centralized push notification copy, grouped by the event that triggers it.
// Mirrors the Strings.* organization in the iOS app (batsignal/Strings/).
Object.defineProperty(exports, "__esModule", { value: true });
exports.Strings = void 0;
exports.Strings = {
    common: {
        someone: "Someone",
    },
    event: {
        createdTitle: (creatorName) => `${creatorName} sent a signal`,
        endedTitle: (creatorName) => `${creatorName} ended their signal`,
        startedTitle: (creatorName) => `${creatorName} is starting now`,
        updatedTitle: (creatorName) => `${creatorName} updated their signal`,
        body: (activity, emoji) => (emoji ? `${emoji} ${activity}` : activity),
    },
    friends: {
        requestTitle: "New friend request",
        requestBody: (fromName) => `${fromName} wants to bool`,
        acceptedTitle: "Friend request accepted",
        acceptedBody: (toName) => `${toName} accepted your friend request`,
    },
};
//# sourceMappingURL=strings.js.map