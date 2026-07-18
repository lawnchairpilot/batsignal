// Centralized push notification copy, grouped by the event that triggers it.
// Mirrors the Strings.* organization in the iOS app (batsignal/Strings/).

export const Strings = {
  common: {
    someone: "Someone",
  },

  event: {
    createdTitle: (creatorName: string) => `${creatorName} sent a signal`,
    endedTitle: (creatorName: string) => `${creatorName} ended their signal`,
    startedTitle: (creatorName: string) => `${creatorName} is starting now`,
    updatedTitle: (creatorName: string) => `${creatorName} updated their signal`,
    body: (activity: string, emoji?: string) => (emoji ? `${emoji} ${activity}` : activity),
  },

  friends: {
    requestTitle: "New friend request",
    requestBody: (fromName: string) => `${fromName} wants to bool`,
    acceptedTitle: "Friend request accepted",
    acceptedBody: (toName: string) => `${toName} accepted your friend request`,
  },
};
