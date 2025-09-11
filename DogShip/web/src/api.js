import { auth } from './auth';
export const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:4242';

export async function authFetch(path, options = {}) {
  const user = auth.currentUser;
  const token = user ? await user.getIdToken() : null;
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {})
  };
  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try { const data = await res.json(); msg = data.error || msg; } catch {}
    throw new Error(msg);
  }
  return res.json();
}

export const Api = {
  createTrip: (payload) => authFetch('/trips', { method: 'POST', body: JSON.stringify(payload) }),
  listMyTrips: (uid) => authFetch(`/trips/user/${uid}`),
  getTripFinance: (tripId) => authFetch(`/trips/${tripId}/finance`),

  getBidsForTrip: (tripId) => authFetch(`/bids/${tripId}`),
  acceptBid: (bidId) => authFetch(`/bids/${bidId}/accept`, { method: 'POST' }),
  placeBid: (tripId, payload) => authFetch(`/bids/${tripId}`, { method: 'POST', body: JSON.stringify(payload) }),
  myBids: () => authFetch('/bids/mine'),
  awardedTrips: () => authFetch('/bids/awarded'),

  getUserProfile: (userId) => authFetch(`/users/${userId}/profile`),
  getUserReviews: (userId, limit=10) => authFetch(`/users/${userId}/reviews?limit=${limit}`),

  chatList: (bidId, since) => authFetch(`/chat/messages?bidId=${bidId}${since ? ` &since=${encodeURIComponent(since)}` : ''}`),
  chatSend: (bidId, body) => authFetch('/chat/send', { method: 'POST', body: JSON.stringify({ bidId, body }) })
};
