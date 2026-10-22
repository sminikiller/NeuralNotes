// Product proposal only. Prices are not activated subscriptions.
export const proposedPlans = Object.freeze({
  free: { priceEUR: 0, dailyCredits: 10, monthlyCredits: 100, storageBytes: 256 * 1024 * 1024 },
  study: { priceEUR: 4.99, dailyCredits: 50, monthlyCredits: 500, storageBytes: 2 * 1024 ** 3 },
  pro: { priceEUR: 9.99, dailyCredits: 150, monthlyCredits: 2000, storageBytes: 10 * 1024 ** 3 },
  team: { priceEUR: 24.99, dailyCredits: 300, monthlyCredits: 3000, storageBytes: 20 * 1024 ** 3 }
});
