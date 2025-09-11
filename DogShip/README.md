# DogShip

Dog transport marketplace (web + iOS/Android) with bidding, pre-bid chat, reviews, Stripe Connect (manual capture), push notifications, role-based dashboards, and Postgres backend.

## Apps
- **backend/** — Node/Express + Postgres + Firebase Admin auth + Stripe Connect + CORS
- **web/** — React + Vite + Firebase Auth + Stripe Elements
- **mobile (Expo)** — React Native + Stripe Payment Sheet + push + chat

## Quick Start

### 1) Database
```bash
psql $DATABASE_URL -f backend/db/schema.sql
```

### 2) Backend
Copy `backend/.env.example` → `backend/.env` and set:
- `DATABASE_URL`
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- `PLATFORM_FEE_PERCENT` (e.g. `15`)
- `BASE_URL` (e.g. `http://localhost:4242` or your prod URL)
- `WEB_ORIGIN` (e.g. `http://localhost:5173` or your web domain)
- Firebase Admin creds: `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`

Run:
```bash
cd backend
npm install
npm run dev
```

### 3) Web
Copy `web/.env.example` → `web/.env`:
- `VITE_API_BASE=http://localhost:4242`
- `VITE_FIREBASE_*`
- `VITE_STRIPE_PUBLISHABLE_KEY`

Run:
```bash
cd web
npm install
npm run dev
```

### 4) Mobile (Expo)
Set env (e.g. app config or shell):
- `EXPO_PUBLIC_API_BASE` → your backend URL (LAN IP for device testing)
- `EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY`
- `EXPO_PUBLIC_FIREBASE_*`

Run:
```bash
npm install
npx expo start
```

### Stripe webhook (local)
```bash
stripe listen --forward-to localhost:4242/stripe/webhook
```
