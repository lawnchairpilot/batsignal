// Centralized push notification copy, grouped by the event that triggers it.
// Mirrors the Strings.* organization in the iOS app (batsignal/Strings/).

export const Strings = {
  common: {
    someone: "Someone",
  },

  event: {
    createdTitle: (creatorName: string) => `${creatorName} sent a signal`,
    updatedTitle: (creatorName: string) => `${creatorName} updated their signal`,
    body: (activity: string, emoji?: string) => (emoji ? `${emoji} ${activity}` : activity),
    joinedTitle: (joinerName: string) => `${joinerName} is in`,
    joinedBody: (joinerName: string, activity: string) => `${joinerName} joined ${activity}`,
    commentTitle: (commenterName: string) => `${commenterName} commented`,
    commentBody: (text: string) => text,
  },

  friends: {
    requestTitle: "New friend request",
    requestBody: (fromName: string) => `${fromName} wants to bool`,
    acceptedTitle: "Friend request accepted",
    acceptedBody: (toName: string) => `${toName} accepted your friend request`,
  },
};
