#!/usr/bin/env bash
set -euo pipefail

# DogShip scaffolder: backend (Express + Postgres + Firebase Admin + Stripe Connect) +
# web (React + Vite + Firebase Auth + Stripe Elements) +
# mobile (Expo + Stripe Payment Sheet + Push) +
# bidding, platform fee, reviews/ratings, avg response time, pre-bid chat, notifications, market feed.

ROOT_DIR="$(pwd)/DogShip"
mkdir -p "$ROOT_DIR"
cd "$ROOT_DIR"

say() { printf "\n\033[1;32m%s\033[0m\n" "$*"; }

say "Creating DogShip monorepo at: $ROOT_DIR"

# ────────────────────────────────────────────────────────────────────────────────
# .gitignore and README
# ────────────────────────────────────────────────────────────────────────────────
cat > .gitignore <<'EOF'
# Node
node_modules/
npm-debug.log*
yarn-error.log
.pnpm-debug.log

# Expo / RN
.expo/
.expo-shared/

# Build
dist/
build/
web/.vite/
web/.cache/
*.zip

# Env
.env
.env.*
backend/.env
web/.env

# macOS
.DS_Store

# Logs
logs
*.log
EOF

cat > README.md <<'EOF'
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
EOF

say "Scaffolding backend…"
mkdir -p backend/{db,middleware,routes,utils}

cat > backend/package.json <<'EOF'
{
  "name": "dogship-backend",
  "version": "1.0.0",
  "main": "server.js",
  "type": "commonjs",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "axios": "^1.4.0",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3",
    "express": "^4.18.2",
    "firebase-admin": "^12.1.0",
    "node-fetch": "2",
    "pg": "^8.11.3",
    "stripe": "^12.13.0"
  },
  "devDependencies": {
    "nodemon": "^2.0.22"
  }
}
EOF

cat > backend/.env.example <<'EOF'
PORT=4242
BASE_URL=http://localhost:4242
WEB_ORIGIN=http://localhost:5173

DATABASE_URL=postgresql://user:password@localhost:5432/dogship

STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
PLATFORM_FEE_PERCENT=15

CHECKR_API_KEY=checkr_test_xxx

FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk@project-id.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----"
EOF

cat > backend/db/schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  firebase_uid TEXT UNIQUE NOT NULL,
  role TEXT CHECK (role IN ('owner','transporter')) NOT NULL,
  email TEXT NOT NULL,
  stripe_account_id TEXT,
  expo_push_token TEXT,
  notification_prefs JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trips (
  id SERIAL PRIMARY KEY,
  owner_id INT REFERENCES users(id) ON DELETE CASCADE,
  transporter_id INT REFERENCES users(id) ON DELETE SET NULL,
  pickup_location TEXT NOT NULL,
  dropoff_location TEXT NOT NULL,
  dog_info JSONB,
  status TEXT CHECK (status IN ('requested','accepted','in_transit','delivered','cancelled')) DEFAULT 'requested',
  payment_intent_id TEXT,
  total_amount_cents INT DEFAULT 0,
  platform_fee_cents INT DEFAULT 0,
  transporter_earnings_cents INT DEFAULT 0,
  winning_bid_id INT,
  accepted_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bids (
  id SERIAL PRIMARY KEY,
  trip_id INT REFERENCES trips(id) ON DELETE CASCADE,
  transporter_id INT REFERENCES users(id) ON DELETE CASCADE,
  amount_cents INT NOT NULL,
  eta_hours INT,
  note TEXT,
  status TEXT CHECK (status IN ('pending','accepted','rejected')) DEFAULT 'pending',
  platform_fee_cents INT DEFAULT 0,
  transporter_earnings_cents INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  last_message_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reviews (
  id SERIAL PRIMARY KEY,
  trip_id INT REFERENCES trips(id) ON DELETE CASCADE,
  reviewer_user_id INT REFERENCES users(id) ON DELETE CASCADE,
  reviewee_user_id INT REFERENCES users(id) ON DELETE CASCADE,
  rating INT CHECK (rating BETWEEN 1 AND 5) NOT NULL,
  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (trip_id, reviewer_user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id SERIAL PRIMARY KEY,
  bid_id INT REFERENCES bids(id) ON DELETE CASCADE,
  sender_user_id INT REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  read_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_trips_status ON trips(status);
CREATE INDEX IF NOT EXISTS idx_trips_accepted_at ON trips(accepted_at);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee ON reviews(reviewee_user_id);
EOF

cat > backend/db/index.js <<'EOF'
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
module.exports = { query: (text, params) => pool.query(text, params), pool };
EOF

cat > backend/middleware/auth.js <<'EOF'
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    }),
  });
}

module.exports = async function verifyFirebaseToken(req, res, next) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Bearer ')) return res.status(401).json({ error: 'Unauthorized' });
  const token = h.split(' ')[1];
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded;
    next();
  } catch (e) {
    console.error(e);
    res.status(401).json({ error: 'Invalid token' });
  }
};
EOF

cat > backend/middleware/roles.js <<'EOF'
const db = require('../db');
const requireRole = (allowed) => {
  return async (req, res, next) => {
    try {
      const uid = req.user?.uid;
      const r = await db.query('SELECT role FROM users WHERE firebase_uid=$1', [uid]);
      if (!r.rows.length) return res.status(403).json({ error: 'User not found in DB' });
      const role = r.rows[0].role;
      if (!allowed.includes(role)) return res.status(403).json({ error: 'Forbidden: insufficient role' });
      req.role = role;
      next();
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: 'Role check failed' });
    }
  };
};
module.exports = requireRole;
EOF

cat > backend/utils/push.js <<'EOF'
const fetch = require('node-fetch');
async function sendExpoPushAsync(messages) {
  const chunks = [];
  const CHUNK_SIZE = 90;
  for (let i = 0; i < messages.length; i += CHUNK_SIZE) chunks.push(messages.slice(i, i + CHUNK_SIZE));
  const tickets = [];
  for (const chunk of chunks) {
    const res = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(chunk)
    });
    tickets.push(await res.json());
  }
  return tickets;
}
module.exports = { sendExpoPushAsync };
EOF

cat > backend/routes/notifications.js <<'EOF'
const express = require('express');
const db = require('../db');
const router = express.Router();

router.post('/register', async (req, res) => {
  try {
    const uid = req.user?.uid;
    const { expoPushToken } = req.body;
    if (!uid || !expoPushToken) return res.status(400).json({ error: 'Missing uid or token' });
    await db.query('UPDATE users SET expo_push_token=$1 WHERE firebase_uid=$2', [expoPushToken, uid]);
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/stripe.js <<'EOF'
const express = require('express');
const router = express.Router();
const bodyParser = require('body-parser');
const db = require('../db');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// webhook needs raw
router.use('/webhook', bodyParser.raw({ type: 'application/json' }));

router.post('/webhook', async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.log('Webhook signature verification failed.', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }
  switch (event.type) {
    case 'payment_intent.captured':
      // Update logs or trip audit if needed
      break;
    default:
      break;
  }
  res.json({ received: true });
});

router.post('/capture-from-trip', async (req, res) => {
  try {
    const { tripId } = req.body;
    const row = await db.query('SELECT payment_intent_id FROM trips WHERE id=$1', [tripId]);
    if (!row.rows.length || !row.rows[0].payment_intent_id) return res.status(400).json({ error: 'No PaymentIntent for trip' });
    const pi = await stripe.paymentIntents.capture(row.rows[0].payment_intent_id);
    res.json({ captured: true, paymentIntent: pi });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/checkr.js <<'EOF'
const express = require('express');
const router = express.Router();
const axios = require('axios');

router.post('/create-candidate', async (req, res) => {
  try {
    const { firstName, lastName, email } = req.body;
    const response = await axios.post('https://api.checkr.com/v1/candidates', {
      given_name: firstName, family_name: lastName, email
    }, { auth: { username: process.env.CHECKR_API_KEY, password: '' } });
    res.json(response.data);
  } catch (e) {
    console.error(e.response?.data || e.message);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/market.js <<'EOF'
const express = require('express');
const db = require('../db');
const requireRole = require('../middleware/roles');
const router = express.Router();

router.get('/open-trips', requireRole(['transporter']), async (req, res) => {
  try {
    const rows = await db.query(
      `SELECT t.id, t.pickup_location, t.dropoff_location, t.status, t.created_at,
              (SELECT COUNT(*) FROM bids b WHERE b.trip_id=t.id) as bid_count
       FROM trips t
       WHERE t.status='requested'
       ORDER BY t.created_at DESC
       LIMIT 100`
    );
    res.json(rows.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/chat.js <<'EOF'
const express = require('express');
const db = require('../db');
const router = express.Router();
const { sendExpoPushAsync } = require('../utils/push');

async function userByUid(uid){
  const u = await db.query('SELECT id, role FROM users WHERE firebase_uid=$1', [uid]);
  if(!u.rows.length) throw new Error('User not found');
  return u.rows[0];
}
async function ensureParticipant(userId, bidId){
  const r = await db.query(
    `SELECT t.owner_id, b.transporter_id
     FROM bids b JOIN trips t ON t.id=b.trip_id
     WHERE b.id=$1`, [bidId]
  );
  if(!r.rows.length) return false;
  const { owner_id, transporter_id } = r.rows[0];
  return userId === owner_id || userId === transporter_id;
}

// List messages
router.get('/messages', async (req, res) => {
  try {
    const uid = req.user.uid;
    const { bidId, since } = req.query;
    if(!bidId) return res.status(400).json({ error: 'bidId required' });
    const me = await userByUid(uid);
    const ok = await ensureParticipant(me.id, bidId);
    if(!ok) return res.status(403).json({ error: 'Forbidden' });

    const params = [bidId];
    let sql = 'SELECT m.id, m.bid_id, m.sender_user_id, m.body, m.created_at FROM messages m WHERE m.bid_id=$1';
    if(since){ params.push(since); sql += ` AND m.created_at > $2`; }
    sql += ' ORDER BY m.created_at ASC';

    const rows = await db.query(sql, params);
    res.json(rows.rows);
  } catch(e){
    console.error(e); res.status(500).json({ error: e.message });
  }
});

// Send
router.post('/send', async (req, res) => {
  try {
    const uid = req.user.uid;
    const { bidId, body } = req.body;
    if(!bidId || !body) return res.status(400).json({ error: 'bidId and body required' });
    const me = await userByUid(uid);
    const ok = await ensureParticipant(me.id, bidId);
    if(!ok) return res.status(403).json({ error: 'Forbidden' });

    const row = await db.query(
      `INSERT INTO messages (bid_id, sender_user_id, body)
       VALUES ($1, $2, $3) RETURNING id, bid_id, sender_user_id, body, created_at`,
      [bidId, me.id, body]
    );

    await db.query('UPDATE bids SET last_message_at=NOW() WHERE id=$1', [bidId]);

    const ot = await db.query(
      `SELECT u.expo_push_token, t.owner_id, b.transporter_id
         FROM bids b JOIN trips t ON t.id=b.trip_id
         JOIN users u ON (CASE WHEN $2 = t.owner_id THEN b.transporter_id ELSE t.owner_id END) = u.id
       WHERE b.id=$1`,
      [bidId, me.id]
    );
    const tok = ot.rows[0]?.expo_push_token;
    if(tok){
      await sendExpoPushAsync([{ to: tok, title: 'New message', body: body.slice(0,100), data: { type:'chat', bidId } }]);
    }

    res.json(row.rows[0]);
  } catch(e){
    console.error(e); res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/users.js <<'EOF'
const express = require('express');
const db = require('../db');
const router = express.Router();

router.get('/:userId/profile', async (req, res) => {
  try {
    const { userId } = req.params;
    const user = await db.query('SELECT id, email, role FROM users WHERE id=$1', [userId]);
    if (!user.rows.length) return res.status(404).json({ error: 'User not found' });

    const ratings = await db.query(
      `SELECT COUNT(*)::int AS review_count, COALESCE(AVG(rating),0)::float AS avg_rating
       FROM reviews WHERE reviewee_user_id=$1`, [userId]
    );
    const response = await db.query(
      `SELECT COALESCE(AVG(EXTRACT(EPOCH FROM (b.created_at - t.created_at))/60),0)::float AS avg_response_minutes
       FROM bids b JOIN trips t ON t.id=b.trip_id WHERE b.transporter_id=$1`, [userId]
    );
    const trips = await db.query(
      `SELECT COUNT(*)::int AS completed_trips FROM trips WHERE transporter_id=$1 AND status='delivered'`, [userId]
    );

    res.json({
      id: user.rows[0].id,
      email: user.rows[0].email,
      role: user.rows[0].role,
      avg_rating: ratings.rows[0].avg_rating,
      review_count: ratings.rows[0].review_count,
      avg_response_minutes: response.rows[0].avg_response_minutes,
      completed_trips: trips.rows[0].completed_trips
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

router.get('/:userId/reviews', async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = Math.min(parseInt(req.query.limit || '10', 10), 50);
    const rows = await db.query(
      `SELECT r.id, r.rating, r.comment, r.created_at, u.email AS reviewer_email
       FROM reviews r JOIN users u ON u.id = r.reviewer_user_id
       WHERE r.reviewee_user_id=$1
       ORDER BY r.created_at DESC
       LIMIT $2`, [userId, limit]
    );
    res.json(rows.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/reviews.js <<'EOF'
const express = require('express');
const db = require('../db');
const requireRole = require('../middleware/roles');
const router = express.Router();

router.post('/trip/:tripId/owner-to-transporter', requireRole(['owner']), async (req, res) => {
  try {
    const { tripId } = req.params;
    const { rating, comment } = req.body;
    const reviewerUid = req.user.uid;

    const reviewer = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [reviewerUid]);
    if (!reviewer.rows.length) return res.status(400).json({ error: 'Reviewer not found' });
    const trip = await db.query('SELECT owner_id, transporter_id FROM trips WHERE id=$1', [tripId]);
    if (!trip.rows.length) return res.status(404).json({ error: 'Trip not found' });
    if (trip.rows[0].owner_id !== reviewer.rows[0].id) return res.status(403).json({ error: 'Not your trip' });

    const review = await db.query(
      `INSERT INTO reviews (trip_id, reviewer_user_id, reviewee_user_id, rating, comment)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (trip_id, reviewer_user_id) DO UPDATE SET rating=EXCLUDED.rating, comment=EXCLUDED.comment
       RETURNING *`,
      [tripId, reviewer.rows[0].id, trip.rows[0].transporter_id, rating, comment]
    );
    res.json(review.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

router.post('/trip/:tripId/transporter-to-owner', requireRole(['transporter']), async (req, res) => {
  try {
    const { tripId } = req.params;
    const { rating, comment } = req.body;
    const reviewerUid = req.user.uid;

    const reviewer = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [reviewerUid]);
    if (!reviewer.rows.length) return res.status(400).json({ error: 'Reviewer not found' });
    const trip = await db.query('SELECT owner_id, transporter_id FROM trips WHERE id=$1', [tripId]);
    if (!trip.rows.length) return res.status(404).json({ error: 'Trip not found' });
    if (trip.rows[0].transporter_id !== reviewer.rows[0].id) return res.status(403).json({ error: 'Not your trip' });

    const review = await db.query(
      `INSERT INTO reviews (trip_id, reviewer_user_id, reviewee_user_id, rating, comment)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (trip_id, reviewer_user_id) DO UPDATE SET rating=EXCLUDED.rating, comment=EXCLUDED.comment
       RETURNING *`,
      [tripId, reviewer.rows[0].id, trip.rows[0].owner_id, rating, comment]
    );
    res.json(review.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/bids.js <<'EOF'
const express = require('express');
const db = require('../db');
const requireRole = require('../middleware/roles');
const router = express.Router();
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// Place bid (transporter)
router.post('/:tripId', requireRole(['transporter']), async (req, res) => {
  try {
    const uid = req.user.uid;
    const { tripId } = req.params;
    const { amountCents, etaHours, note } = req.body;
    const userRes = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [uid]);
    if (!userRes.rows.length) return res.status(400).json({ error: 'Transporter not found' });
    const transporterId = userRes.rows[0].id;

    const bidRes = await db.query(
      `INSERT INTO bids (trip_id, transporter_id, amount_cents, eta_hours, note)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [tripId, transporterId, amountCents, etaHours, note]
    );

    // notify owner
    const owner = await db.query(
      `SELECT u.expo_push_token FROM trips t JOIN users u ON u.id=t.owner_id WHERE t.id=$1`, [tripId]
    );
    const ownerToken = owner.rows[0]?.expo_push_token;
    if (ownerToken) {
      const { sendExpoPushAsync } = require('../utils/push');
      await sendExpoPushAsync([{ to: ownerToken, title: 'New bid received', body: 'Open the app to review bids', data: { type: 'new_bid', tripId: Number(tripId) } }]);
    }

    res.json(bidRes.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Bids for a trip (owner)
router.get('/:tripId', requireRole(['owner']), async (req, res) => {
  try {
    const { tripId } = req.params;
    const bidsRes = await db.query(
      `SELECT b.*, u.email AS transporter_email,
              COALESCE(avg_r.avg_rating,0) as avg_rating,
              COALESCE(avg_r.review_count,0) as review_count,
              EXTRACT(EPOCH FROM (b.created_at - t.created_at))/60 as response_time_minutes
       FROM bids b
       JOIN users u ON b.transporter_id = u.id
       JOIN trips t ON b.trip_id = t.id
       LEFT JOIN (
         SELECT reviewee_user_id, AVG(rating) as avg_rating, COUNT(*) as review_count
         FROM reviews GROUP BY reviewee_user_id
       ) avg_r ON avg_r.reviewee_user_id = b.transporter_id
       WHERE b.trip_id=$1
       ORDER BY b.amount_cents ASC`,
      [tripId]
    );
    res.json(bidsRes.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Accept a bid (owner)
router.post('/:bidId/accept', requireRole(['owner']), async (req, res) => {
  try {
    const { bidId } = req.params;
    const bidRes = await db.query(
      `SELECT b.*, t.owner_id, t.id as trip_id, u.firebase_uid as transporter_uid, u.email as transporter_email
       FROM bids b
       JOIN trips t ON t.id = b.trip_id
       JOIN users u ON u.id = b.transporter_id
       WHERE b.id=$1`, [bidId]
    );
    if (!bidRes.rows.length) return res.status(404).json({ error: 'Bid not found' });
    const bid = bidRes.rows[0];

    const feePercent = parseFloat(process.env.PLATFORM_FEE_PERCENT || 15);
    const platformFee = Math.round(bid.amount_cents * (feePercent / 100));
    const transporterEarnings = bid.amount_cents - platformFee;

    const acctRes = await db.query('SELECT stripe_account_id FROM users WHERE id=$1', [bid.transporter_id]);
    const stripeAccountId = acctRes.rows[0]?.stripe_account_id;
    if (!stripeAccountId) return res.status(400).json({ error: 'Transporter not onboarded with Stripe' });

    const paymentIntent = await stripe.paymentIntents.create({
      amount: bid.amount_cents,
      currency: 'usd',
      capture_method: 'manual',
      payment_method_types: ['card'],
      description: `DogShip trip ${bid.trip_id} - bid ${bid.id}`,
      transfer_data: { destination: stripeAccountId },
      application_fee_amount: platformFee,
      metadata: { trip_id: String(bid.trip_id), bid_id: String(bid.id), transporter_user_id: String(bid.transporter_id) }
    });

    const updatedBidRes = await db.query(
      `UPDATE bids SET status='accepted', platform_fee_cents=$2, transporter_earnings_cents=$3
       WHERE id=$1 RETURNING *`, [bidId, platformFee, transporterEarnings]
    );
    const updatedBid = updatedBidRes.rows[0];

    await db.query(`UPDATE bids SET status='rejected' WHERE trip_id=$1 AND id<>$2`, [updatedBid.trip_id, updatedBid.id]);

    await db.query(
      `UPDATE trips
       SET transporter_id=$1, winning_bid_id=$2, status='accepted',
           total_amount_cents=$3, platform_fee_cents=$4, transporter_earnings_cents=$5,
           payment_intent_id=$6, accepted_at=NOW(), updated_at=NOW()
       WHERE id=$7`,
      [updatedBid.transporter_id, updatedBid.id, updatedBid.amount_cents, platformFee, transporterEarnings, paymentIntent.id, updatedBid.trip_id]
    );

    // notify transporter
    const tkn = await db.query('SELECT expo_push_token FROM users WHERE id=$1', [updatedBid.transporter_id]);
    const tok = tkn.rows[0]?.expo_push_token;
    if (tok) {
      const { sendExpoPushAsync } = require('../utils/push');
      await sendExpoPushAsync([{ to: tok, title: 'Your bid was accepted', body: `Trip #${updatedBid.trip_id}`, data: { type: 'bid_accepted', tripId: updatedBid.trip_id } }]);
    }

    res.json({
      success: true,
      paymentIntentId: paymentIntent.id,
      clientSecret: paymentIntent.client_secret,
      winningBid: updatedBid,
      feePercent,
      breakdown: { total: updatedBid.amount_cents, platformFee, transporterEarnings }
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Mine
router.get('/mine', requireRole(['transporter']), async (req, res) => {
  try {
    const uid = req.user.uid;
    const u = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [uid]);
    if (!u.rows.length) return res.status(400).json({ error: 'User not found' });
    const transporterId = u.rows[0].id;

    const rows = await db.query(
      `SELECT b.*, t.pickup_location, t.dropoff_location, t.status as trip_status
       FROM bids b JOIN trips t ON t.id = b.trip_id
       WHERE b.transporter_id=$1
       ORDER BY b.created_at DESC`, [transporterId]
    );
    res.json(rows.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Awarded
router.get('/awarded', requireRole(['transporter']), async (req, res) => {
  try {
    const uid = req.user.uid;
    const u = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [uid]);
    if (!u.rows.length) return res.status(400).json({ error: 'User not found' });
    const transporterId = u.rows[0].id;

    const rows = await db.query(
      `SELECT t.*, b.amount_cents, b.transporter_earnings_cents, b.platform_fee_cents
       FROM trips t JOIN bids b ON b.id = t.winning_bid_id
       WHERE t.transporter_id=$1
       ORDER BY t.accepted_at DESC NULLS LAST`, [transporterId]
    );
    res.json(rows.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/routes/trips.js <<'EOF'
const express = require('express');
const db = require('../db');
const requireRole = require('../middleware/roles');
const axios = require('axios');
const { sendExpoPushAsync } = require('../utils/push');
const router = express.Router();

// Create trip (owner)
router.post('/', requireRole(['owner']), async (req, res) => {
  try {
    const uid = req.user.uid;
    const { pickupLocation, dropoffLocation, dogInfo } = req.body;
    const u = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [uid]);
    if (!u.rows.length) return res.status(400).json({ error: 'Owner not found' });
    const ownerId = u.rows[0].id;

    const tripRes = await db.query(
      `INSERT INTO trips (owner_id, pickup_location, dropoff_location, dog_info)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [ownerId, pickupLocation, dropoffLocation, dogInfo || {}]
    );

    // notify all transporters (MVP)
    const ts = await db.query("SELECT expo_push_token FROM users WHERE role='transporter' AND expo_push_token IS NOT NULL");
    const messages = ts.rows.map(r => ({
      to: r.expo_push_token,
      title: 'New dog trip available',
      body: `${pickupLocation} → ${dropoffLocation}`,
      data: { type: 'new_trip', tripId: tripRes.rows[0].id }
    }));
    if (messages.length) await sendExpoPushAsync(messages);

    res.json(tripRes.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// List my trips
router.get('/user/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const u = await db.query('SELECT id FROM users WHERE firebase_uid=$1', [uid]);
    if (!u.rows.length) return res.status(400).json({ error: 'User not found' });
    const userId = u.rows[0].id;

    const tripsRes = await db.query(
      'SELECT * FROM trips WHERE owner_id=$1 OR transporter_id=$1 ORDER BY created_at DESC',
      [userId]
    );
    res.json(tripsRes.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Finance summary
router.get('/:tripId/finance', requireRole(['owner']), async (req, res) => {
  try {
    const { tripId } = req.params;
    const result = await db.query(
      `SELECT id, status, total_amount_cents, platform_fee_cents, transporter_earnings_cents, accepted_at
       FROM trips WHERE id=$1`, [tripId]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Trip not found' });
    res.json(result.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

// Mark delivered (owner) -> capture
router.post('/:tripId/mark-delivered', requireRole(['owner']), async (req, res) => {
  try {
    const { tripId } = req.params;
    await db.query("UPDATE trips SET status='delivered', updated_at=NOW() WHERE id=$1", [tripId]);
    const captureRes = await axios.post(`${process.env.BASE_URL}/stripe/capture-from-trip`, { tripId }, { headers: { Authorization: req.headers.authorization } });
    // notify owner
    const own = await db.query('SELECT u.expo_push_token FROM trips t JOIN users u ON u.id=t.owner_id WHERE t.id=$1', [tripId]);
    const ownTok = own.rows[0]?.expo_push_token;
    if (ownTok) {
      await sendExpoPushAsync([{ to: ownTok, title: 'Trip delivered', body: 'Payment captured. Please leave a review.', data: { type: 'delivered', tripId: Number(tripId) } }]);
    }
    res.json({ delivered: true, capture: captureRes.data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});
module.exports = router;
EOF

cat > backend/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const verifyFirebaseToken = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 4242;

app.use(cors({ origin: [process.env.WEB_ORIGIN || 'http://localhost:5173'], credentials: false }));
app.use(bodyParser.json());

// Routers
const stripeRouter = require('./routes/stripe');
const checkrRouter = require('./routes/checkr');
const tripsRouter = require('./routes/trips');
const bidsRouter = require('./routes/bids');
const usersRouter = require('./routes/users');
const marketRouter = require('./routes/market');
const chatRouter = require('./routes/chat');
const notificationsRouter = require('./routes/notifications');

app.get('/', (req, res) => res.send('DogShip Backend Up'));

app.use('/trips', verifyFirebaseToken, tripsRouter);
app.use('/bids', verifyFirebaseToken, bidsRouter);
app.use('/users', verifyFirebaseToken, usersRouter);
app.use('/market', verifyFirebaseToken, marketRouter);
app.use('/chat', verifyFirebaseToken, chatRouter);
app.use('/notifications', verifyFirebaseToken, notificationsRouter);

// Stripe webhook (raw body inside)
app.use('/stripe', stripeRouter);

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
EOF

say "Scaffolding web…"
mkdir -p web/src/pages

cat > web/package.json <<'EOF'
{
  "name": "dogship-web",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@stripe/react-stripe-js": "^2.6.2",
    "@stripe/stripe-js": "^2.5.0",
    "firebase": "^10.12.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.26.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.0",
    "vite": "^5.0.0"
  }
}
EOF

cat > web/vite.config.js <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({ plugins: [react()] });
EOF

cat > web/index.html <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>DogShip Web</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

cat > web/.env.example <<'EOF'
VITE_API_BASE=http://localhost:4242
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=...
VITE_FIREBASE_PROJECT_ID=...
VITE_STRIPE_PUBLISHABLE_KEY=pk_test_123
EOF

cat > web/src/main.jsx <<'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';

createRoot(document.getElementById('root')).render(
  <BrowserRouter>
    <App />
  </BrowserRouter>
);
EOF

cat > web/src/App.jsx <<'EOF'
import React from 'react';
import { Routes, Route, Link } from 'react-router-dom';
import Login from './pages/Login';
import OwnerDashboard from './pages/OwnerDashboard';
import TransporterDashboard from './pages/TransporterDashboard';
import TripBids from './pages/TripBids';
import StripeConfirm from './pages/StripeConfirm';
import Chat from './pages/Chat';

export default function App() {
  return (
    <div style={{ maxWidth: 900, margin: '0 auto', padding: 16 }}>
      <h1>DogShip Web</h1>
      <nav style={{ display: 'flex', gap: 12 }}>
        <Link to="/">Login</Link>
        <Link to="/owner">Owner</Link>
        <Link to="/transporter">Transporter</Link>
      </nav>
      <Routes>
        <Route path="/" element={<Login />} />
        <Route path="/owner" element={<OwnerDashboard />} />
        <Route path="/transporter" element={<TransporterDashboard />} />
        <Route path="/trip/:tripId/bids" element={<TripBids />} />
        <Route path="/confirm" element={<StripeConfirm />} />
        <Route path="/chat" element={<Chat />} />
      </Routes>
    </div>
  );
}
EOF

cat > web/src/auth.js <<'EOF'
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut } from 'firebase/auth';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const AuthApi = {
  login: (email, password) => signInWithEmailAndPassword(auth, email, password),
  signup: (email, password) => createUserWithEmailAndPassword(auth, email, password),
  logout: () => signOut(auth)
};
EOF

cat > web/src/api.js <<'EOF'
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
EOF

cat > web/src/pages/Login.jsx <<'EOF'
import React, { useState } from 'react';
import { AuthApi } from '../auth';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  return (
    <div>
      <h2>Login / Signup</h2>
      <input placeholder="email" value={email} onChange={e=>setEmail(e.target.value)} />
      <input placeholder="password" type="password" value={password} onChange={e=>setPassword(e.target.value)} />
      <div style={{ display:'flex', gap:8 }}>
        <button onClick={() => AuthApi.login(email, password)}>Login</button>
        <button onClick={() => AuthApi.signup(email, password)}>Signup</button>
      </div>
    </div>
  );
}
EOF

cat > web/src/pages/OwnerDashboard.jsx <<'EOF'
import React, { useEffect, useState } from 'react';
import { auth } from '../auth';
import { Api } from '../api';
import { Link } from 'react-router-dom';

export default function OwnerDashboard() {
  const [rows, setRows] = useState([]);
  useEffect(() => { (async () => {
    const uid = auth.currentUser?.uid;
    if (!uid) return;
    setRows(await Api.listMyTrips(uid));
  })(); }, []);

  return (
    <div>
      <h2>My Trips</h2>
      {rows.map(t => (
        <div key={t.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{t.pickup_location}</b> → <b>{t.dropoff_location}</b></div>
          <div>Status: {t.status}</div>
          <Link to={`/trip/${t.id}/bids`}>View Bids</Link>
        </div>
      ))}
    </div>
  );
}
EOF

cat > web/src/pages/TripBids.jsx <<'EOF'
import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Api } from '../api';

const currency = c => `$${(c/100).toFixed(2)}`;

export default function TripBids() {
  const { tripId } = useParams();
  const nav = useNavigate();
  const [rows, setRows] = useState([]);

  useEffect(() => { (async () => {
    setRows(await Api.getBidsForTrip(tripId));
  })(); }, [tripId]);

  const accept = async (bidId) => {
    const resp = await Api.acceptBid(bidId);
    nav('/confirm', { state: { clientSecret: resp.clientSecret, tripId } });
  };

  return (
    <div>
      <h2>Bids</h2>
      {rows.map(b => (
        <div key={b.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{currency(b.amount_cents)}</b> • ETA {b.eta_hours || '?'}h</div>
          <div>⭐ {Number(b.avg_rating||0).toFixed(1)} ({b.review_count}) • Response {Number(b.response_time_minutes||0).toFixed(1)} min</div>
          <div>{b.note || '—'}</div>
          <button onClick={() => accept(b.id)}>Accept & Pay</button>
          <button onClick={() => nav(`/chat?bidId=${b.id}`)} style={{ marginLeft: 8 }}>Message transporter</button>
        </div>
      ))}
    </div>
  );
}
EOF

cat > web/src/pages/StripeConfirm.jsx <<'EOF'
import React, { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { loadStripe } from '@stripe/stripe-js';
import { Elements, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';

const stripePromise = loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY);

function CheckoutInner() {
  const stripe = useStripe();
  const elements = useElements();
  const nav = useNavigate();

  async function onSubmit(e) {
    e.preventDefault();
    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: {},
      redirect: 'if_required'
    });
    if (error) alert(error.message);
    else { alert('Payment confirmed'); nav('/owner'); }
  }
  return (
    <form onSubmit={onSubmit} style={{ maxWidth: 480 }}>
      <PaymentElement />
      <button style={{ marginTop: 12 }}>Pay</button>
    </form>
  );
}

export default function StripeConfirm() {
  const { state } = useLocation();
  const [options, setOptions] = useState(null);
  useEffect(() => { if (state?.clientSecret) setOptions({ clientSecret: state.clientSecret }); }, [state]);
  if (!options) return <div>Missing client secret</div>;
  return (
    <Elements stripe={stripePromise} options={options}>
      <CheckoutInner />
    </Elements>
  );
}
EOF

cat > web/src/pages/TransporterDashboard.jsx <<'EOF'
import React, { useEffect, useState } from 'react';
import { Api, authFetch } from '../api';
import { Link } from 'react-router-dom';

export default function TransporterDashboard() {
  const [open, setOpen] = useState([]);
  const [myBids, setMyBids] = useState([]);

  useEffect(() => { (async () => {
    setOpen(await authFetch('/market/open-trips'));
    setMyBids(await Api.myBids());
  })(); }, []);

  return (
    <div>
      <h2>Open Trips</h2>
      {open.map(t => (
        <div key={t.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{t.pickup_location}</b> → <b>{t.dropoff_location}</b></div>
          <div>{t.bid_count} bids</div>
          <Link to={`/trip/${t.id}/bids`}>View / Place Bid</Link>
        </div>
      ))}

      <h2>My Bids</h2>
      {myBids.map(b => (
        <div key={b.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div>{b.pickup_location} → {b.dropoff_location}</div>
          <div>Amount: ${(b.amount_cents/100).toFixed(2)} • Status: {b.status} • Trip: {b.trip_status}</div>
        </div>
      ))}
    </div>
  );
}
EOF

cat > web/src/pages/Chat.jsx <<'EOF'
import React from 'react';
import { authFetch } from '../api';
import { useLocation } from 'react-router-dom';

export default function Chat(){
  const q = new URLSearchParams(useLocation().search);
  const bidId = q.get('bidId');
  const [msgs, setMsgs] = React.useState([]);
  const [text, setText] = React.useState('');
  const sinceRef = React.useRef(null);

  async function load(){
    const url = sinceRef.current ? `/chat/messages?bidId=${bidId}&since=${encodeURIComponent(sinceRef.current)}` : `/chat/messages?bidId=${bidId}`;
    const rows = await authFetch(url);
    if(rows.length){
      setMsgs(m => [...m, ...rows]);
      sinceRef.current = rows[rows.length-1].created_at;
    }
  }
  React.useEffect(()=>{ load(); const t=setInterval(load, 3000); return ()=>clearInterval(t); }, [bidId]);

  async function send(e){
    e.preventDefault();
    if(!text.trim()) return;
    const m = await authFetch('/chat/send', { method:'POST', body: JSON.stringify({ bidId, body: text })});
    setMsgs(arr => [...arr, m]);
    setText('');
  }

  return (
    <div>
      <h2>Chat</h2>
      <div style={{ border:'1px solid #eee', padding:12, minHeight:240, marginBottom:8 }}>
        {msgs.map(m => (
          <div key={m.id} style={{ marginBottom:8 }}>
            <div><b>{m.sender_user_id}</b> <small>{new Date(m.created_at).toLocaleString()}</small></div>
            <div>{m.body}</div>
          </div>
        ))}
      </div>
      <form onSubmit={send} style={{ display:'flex', gap:8 }}>
        <input value={text} onChange={e=>setText(e.target.value)} placeholder="Message" style={{ flex:1 }} />
        <button>Send</button>
      </form>
    </div>
  );
}
EOF

say "Scaffolding mobile (Expo)…"
mkdir -p screens/{Owner,Transporter,Chat}
mkdir -p utils

cat > package.json <<'EOF'
{
  "name": "dogship-mvp",
  "version": "1.0.0",
  "main": "node_modules/expo/AppEntry.js",
  "scripts": {
    "start": "expo start",
    "android": "expo run:android",
    "ios": "expo run:ios"
  },
  "dependencies": {
    "@react-navigation/native": "^6.0.10",
    "@react-navigation/native-stack": "^6.6.2",
    "@stripe/stripe-react-native": "^0.38.0",
    "expo": "~48.0.0",
    "expo-notifications": "~0.18.1",
    "expo-status-bar": "1.4.2",
    "firebase": "^9.22.0",
    "react": "18.2.0",
    "react-native": "0.71.0",
    "react-native-gesture-handler": "~2.5.0",
    "react-native-safe-area-context": "4.3.1"
  }
}
EOF

cat > App.js <<'EOF'
import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from './firebase';
import { StripeProvider } from '@stripe/stripe-react-native';

// Screens (owner)
import LoginScreen from './screens/LoginScreen';
import OwnerHome from './screens/Owner/HomeScreen';
import OwnerPostTrip from './screens/Owner/PostTripScreen';
import OwnerTripDetail from './screens/Owner/TripDetailScreen';
import BidsScreen from './screens/Owner/BidsScreen';
import BidDetailScreen from './screens/Owner/BidDetailScreen';
import TransporterProfileScreen from './screens/Owner/TransporterProfileScreen';
import LeaveReviewScreen from './screens/Owner/LeaveReviewScreen';

// Screens (transporter)
import TransporterHome from './screens/Transporter/HomeScreen';
import TripApply from './screens/Transporter/TripApplyScreen';
import PlaceBidScreen from './screens/Transporter/PlaceBidScreen';
import MyBidsScreen from './screens/Transporter/MyBidsScreen';
import AwardedTripsScreen from './screens/Transporter/AwardedTripsScreen';
import MarketScreen from './screens/Transporter/MarketScreen';

// Chat
import ChatScreen from './screens/Chat/ChatScreen';

const Stack = createNativeStackNavigator();

export default function App() {
  const [user, setUser] = useState(null);
  const [role, setRole] = useState(null);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setUser(u);
      setRole(u?.displayName || 'owner');
    });
    return unsub;
  }, []);

  const publishableKey = process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY;

  return (
    <StripeProvider publishableKey={publishableKey}>
      <NavigationContainer>
        <Stack.Navigator>
          {!user ? (
            <Stack.Screen name="Login" component={LoginScreen} />
          ) : role === 'transporter' ? (
            <>
              <Stack.Screen name="TransporterHome" component={TransporterHome} />
              <Stack.Screen name="Market" component={MarketScreen} />
              <Stack.Screen name="TripApply" component={TripApply} />
              <Stack.Screen name="PlaceBid" component={PlaceBidScreen} />
              <Stack.Screen name="MyBids" component={MyBidsScreen} />
              <Stack.Screen name="AwardedTrips" component={AwardedTripsScreen} />
              <Stack.Screen name="Chat" component={ChatScreen} />
            </>
          ) : (
            <>
              <Stack.Screen name="OwnerHome" component={OwnerHome} />
              <Stack.Screen name="PostTrip" component={OwnerPostTrip} />
              <Stack.Screen name="TripDetail" component={OwnerTripDetail} />
              <Stack.Screen name="Bids" component={BidsScreen} />
              <Stack.Screen name="BidDetail" component={BidDetailScreen} />
              <Stack.Screen name="TransporterProfile" component={TransporterProfileScreen} />
              <Stack.Screen name="LeaveReview" component={LeaveReviewScreen} />
              <Stack.Screen name="Chat" component={ChatScreen} />
            </>
          )}
        </Stack.Navigator>
      </NavigationContainer>
    </StripeProvider>
  );
}
EOF

cat > firebase.js <<'EOF'
import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: process.env.EXPO_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.EXPO_PUBLIC_FIREBASE_PROJECT_ID
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
EOF

cat > utils/api.js <<'EOF'
import { auth } from '../firebase';
export const API_BASE = process.env.EXPO_PUBLIC_API_BASE || 'http://localhost:4242';

export async function authFetch(path, options = {}) {
  const user = auth.currentUser;
  const token = user ? await user.getIdToken() : null;
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try { const data = await res.json(); msg = data.error || msg; } catch {}
    throw new Error(msg);
  }
  return res.json();
}
EOF

cat > screens/LoginScreen.js <<'EOF'
import React, { useState } from 'react';
import { View, Text, TextInput, Button } from 'react-native';
import { getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword, updateProfile } from 'firebase/auth';

export default function LoginScreen(){
  const [email, setEmail] = useState('');
  const [pass, setPass] = useState('');
  const [role, setRole] = useState('owner');

  async function login(){ await signInWithEmailAndPassword(getAuth(), email, pass); }
  async function signup(){
    const cred = await createUserWithEmailAndPassword(getAuth(), email, pass);
    await updateProfile(cred.user, { displayName: role });
  }

  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:22 }}>DogShip</Text>
      <TextInput placeholder="Email" value={email} onChangeText={setEmail} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <TextInput placeholder="Password" secureTextEntry value={pass} onChangeText={setPass} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Text>Role: (type owner or transporter)</Text>
      <TextInput placeholder="owner | transporter" value={role} onChangeText={setRole} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Button title="Login" onPress={login} />
      <View style={{ height:8 }} />
      <Button title="Sign up" onPress={signup} />
    </View>
  );
}
EOF

cat > screens/Owner/HomeScreen.js <<'EOF'
import React, { useEffect, useState } from 'react';
import { View, Text, Button, FlatList, TouchableOpacity } from 'react-native';
import { auth } from '../../firebase';
import { authFetch } from '../../utils/api';

export default function OwnerHome({ navigation }){
  const [rows, setRows] = useState([]);
  async function load(){
    const uid = auth.currentUser?.uid;
    if (!uid) return;
    const data = await authFetch(`/trips/user/${uid}`);
    setRows(data.filter(t => t.owner_id));
  }
  useEffect(() => { load(); }, []);

  return (
    <View style={{ flex:1, padding:12 }}>
      <Button title="Post Trip" onPress={() => navigation.navigate('PostTrip')} />
      <FlatList data={rows} keyExtractor={x=>String(x.id)}
        renderItem={({ item }) => (
          <TouchableOpacity onPress={() => navigation.navigate('TripDetail', { id: item.id })} style={{ borderWidth:1, padding:12, borderRadius:8, marginVertical:6 }}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>Status: {item.status}</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}
EOF

cat > screens/Owner/PostTripScreen.js <<'EOF'
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function PostTripScreen({ navigation }){
  const [pickup, setPickup] = useState('');
  const [dropoff, setDropoff] = useState('');
  const [dog, setDog] = useState('{"breed":"Labrador"}');

  async function create(){
    try{
      const payload = { pickupLocation: pickup, dropoffLocation: dropoff, dogInfo: JSON.parse(dog || '{}') };
      await authFetch('/trips', { method:'POST', body: JSON.stringify(payload) });
      Alert.alert('Trip posted');
      navigation.goBack();
    }catch(e){ Alert.alert('Error', e.message); }
  }

  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Post Trip</Text>
      <TextInput placeholder="Pickup" value={pickup} onChangeText={setPickup} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <TextInput placeholder="Dropoff" value={dropoff} onChangeText={setDropoff} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Text>Dog JSON</Text>
      <TextInput placeholder='{"breed":"Labrador"}' value={dog} onChangeText={setDog} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Button title="Create Trip" onPress={create} />
    </View>
  );
}
EOF

cat > screens/Owner/TripDetailScreen.js <<'EOF'
import React from 'react';
import { View, Text, Button } from 'react-native';

export default function TripDetailScreen({ route, navigation }){
  const { id } = route.params;
  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Trip #{id}</Text>
      <View style={{ height:8 }} />
      <Button title="View Bids" onPress={() => navigation.navigate('Bids', { tripId: id, feePercent: 15 })} />
    </View>
  );
}
EOF

cat > screens/Owner/BidsScreen.js <<'EOF'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl, Alert, Button } from 'react-native';
import { authFetch } from '../../utils/api';

const currency = (cents) => `$${(cents/100).toFixed(2)}`;

export default function BidsScreen({ route, navigation }) {
  const { tripId, feePercent = 15 } = route.params;
  const [bids, setBids] = useState([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const data = await authFetch(`/bids/${tripId}`);
      setBids(data);
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [tripId]);

  const renderItem = ({ item }) => {
    const platformFee = Math.round(item.amount_cents * (feePercent/100));
    const transporterEarnings = item.amount_cents - platformFee;
    return (
      <TouchableOpacity
        style={{ padding: 12, borderWidth: 1, borderRadius: 8, marginBottom: 10 }}
        onPress={() => navigation.navigate('BidDetail', { bid: item, feePercent })}
      >
        <Text style={{ fontWeight: '700' }}>{currency(item.amount_cents)} • ETA {item.eta_hours || '?'}h</Text>
        <Text>{item.note || '—'}</Text>
        <Text onPress={() => navigation.navigate('TransporterProfile', { userId: item.transporter_id })}
          style={{ textDecorationLine: 'underline' }}>Transporter: {item.transporter_email || item.transporter_id}</Text>
        <Text>⭐ {Number(item.avg_rating||0).toFixed(1)} ({item.review_count}) • Response {Number(item.response_time_minutes||0).toFixed(1)} min</Text>
        <Text>Platform fee {feePercent}%: {currency(platformFee)} • Driver gets {currency(transporterEarnings)}</Text>
        <Text>Status: {item.status}</Text>
        <View style={{ height:8 }} />
        <Button title="Message transporter" onPress={() => navigation.navigate('Chat', { bidId: item.id })} />
      </TouchableOpacity>
    );
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <FlatList
        data={bids}
        keyExtractor={(b) => String(b.id)}
        renderItem={renderItem}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        ListEmptyComponent={!loading && (<Text>No bids yet. Pull to refresh.</Text>)}
      />
    </View>
  );
}
EOF

cat > screens/Owner/BidDetailScreen.js <<'EOF'
import React, { useState } from 'react';
import { View, Text, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';
import { useStripe } from '@stripe/stripe-react-native';

const currency = (cents) => `$${(cents/100).toFixed(2)}`;

export default function BidDetailScreen({ route, navigation }) {
  const { bid, feePercent = 15 } = route.params;
  const [busy, setBusy] = useState(false);
  const { initPaymentSheet, presentPaymentSheet } = useStripe();

  const platformFee = Math.round(bid.amount_cents * (feePercent/100));
  const driverGets = bid.amount_cents - platformFee;

  const accept = async () => {
    try {
      setBusy(true);
      const resp = await authFetch(`/bids/${bid.id}/accept`, { method: 'POST' });
      const { clientSecret } = resp;
      await initPaymentSheet({ paymentIntentClientSecret: clientSecret });
      const { error } = await presentPaymentSheet();
      if (error) throw new Error(error.message);
      Alert.alert('Payment confirmed');
      navigation.popToTop();
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight: '700', fontSize: 18 }}>Bid: {currency(bid.amount_cents)}</Text>
      <Text>ETA: {bid.eta_hours || '?'} hours</Text>
      <Text>Note: {bid.note || '—'}</Text>
      <View style={{ height: 10 }} />
      <Text>Platform fee ({feePercent}%): {currency(platformFee)}</Text>
      <Text>Driver gets: {currency(driverGets)}</Text>
      <View style={{ height: 16 }} />
      <Button title={busy ? 'Accepting…' : 'Accept this bid'} onPress={accept} disabled={busy} />
      <View style={{ height: 8 }} />
      <Button title="Message transporter" onPress={() => navigation.navigate('Chat', { bidId: bid.id })} />
    </View>
  );
}
EOF

cat > screens/Owner/TransporterProfileScreen.js <<'EOF'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, ActivityIndicator } from 'react-native';
import { authFetch } from '../../utils/api';

export default function TransporterProfileScreen({ route }) {
  const { userId } = route.params;
  const [profile, setProfile] = useState(null);
  const [reviews, setReviews] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const p = await authFetch(`/users/${userId}/profile`);
        const r = await authFetch(`/users/${userId}/reviews?limit=20`);
        setProfile(p); setReviews(r);
      } finally { setLoading(false); }
    })();
  }, [userId]);

  if (loading) return <View style={{ flex:1, justifyContent:'center', alignItems:'center' }}><ActivityIndicator /></View>;
  if (!profile) return <View style={{ padding:16 }}><Text>Profile not found.</Text></View>;

  return (
    <View style={{ flex:1, padding:16 }}>
      <Text style={{ fontSize:20, fontWeight:'700' }}>{profile.email}</Text>
      <Text>Role: {profile.role}</Text>
      <Text>⭐ {Number(profile.avg_rating).toFixed(1)} ({profile.review_count} reviews)</Text>
      <Text>Avg response: {Number(profile.avg_response_minutes).toFixed(1)} min</Text>
      <Text>Completed trips: {profile.completed_trips}</Text>

      <View style={{ height:16 }} />
      <Text style={{ fontWeight:'700', fontSize:16 }}>Recent Reviews</Text>
      <FlatList
        data={reviews}
        keyExtractor={(x) => String(x.id)}
        renderItem={({ item }) => (
          <View style={{ borderWidth:1, borderRadius:8, padding:12, marginTop:8 }}>
            <Text>⭐ {item.rating} — {new Date(item.created_at).toLocaleDateString()}</Text>
            <Text>From: {item.reviewer_email}</Text>
            <Text>{item.comment || '—'}</Text>
          </View>
        )}
        ListEmptyComponent={<Text>No reviews yet.</Text>}
      />
    </View>
  );
}
EOF

cat > screens/Owner/LeaveReviewScreen.js <<'EOF'
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function LeaveReviewScreen({ route, navigation }){
  const { tripId } = route.params;
  const [rating, setRating] = useState('5');
  const [comment, setComment] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    try {
      setBusy(true);
      const payload = { rating: Number(rating), comment };
      await authFetch(`/reviews/trip/${tripId}/owner-to-transporter`, { method: 'POST', body: JSON.stringify(payload) });
      Alert.alert('Thanks!', 'Your review has been submitted.');
      navigation.goBack();
    } catch (e) { Alert.alert('Error', e.message); } finally { setBusy(false); }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Rate your driver</Text>
      <TextInput placeholder="Rating (1-5)" keyboardType="number-pad" value={rating} onChangeText={setRating} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="Comment" value={comment} onChangeText={setComment} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <View style={{ height: 12 }} />
      <Button title={busy ? 'Submitting…' : 'Submit Review'} onPress={submit} disabled={busy} />
    </View>
  );
}
EOF

cat > screens/Transporter/HomeScreen.js <<'EOF'
import React from 'react';
import { View, Button } from 'react-native';

export default function TransporterHome({ navigation }){
  return (
    <View style={{ padding:16 }}>
      <Button title="Market" onPress={() => navigation.navigate('Market')} />
      <Button title="My Bids" onPress={() => navigation.navigate('MyBids')} />
      <Button title="Awarded Trips" onPress={() => navigation.navigate('AwardedTrips')} />
    </View>
  );
}
EOF

cat > screens/Transporter/TripApplyScreen.js <<'EOF'
import React from 'react';
import { View, Text, Button } from 'react-native';

export default function TripApplyScreen({ route, navigation }){
  const { id } = route.params;
  return (
    <View style={{ padding:16 }}>
      <Text>Trip #{id}</Text>
      <Button title="Place a Bid" onPress={() => navigation.navigate('PlaceBid', { tripId: id })} />
    </View>
  );
}
EOF

cat > screens/Transporter/PlaceBidScreen.js <<'EOF'
import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function PlaceBidScreen({ route, navigation }) {
  const { tripId } = route.params;
  const [amount, setAmount] = useState('');
  const [eta, setEta] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!amount) return Alert.alert('Enter an amount');
    setBusy(true);
    try {
      const amountCents = Math.round(parseFloat(amount) * 100);
      await authFetch(`/bids/${tripId}`, { method: 'POST', body: JSON.stringify({ amountCents, etaHours: Number(eta) || null, note }) });
      Alert.alert('Bid placed');
      navigation.goBack();
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally { setBusy(false); }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight: '700', fontSize: 18 }}>Place a Bid</Text>
      <TextInput placeholder="Amount (USD)" keyboardType="decimal-pad" value={amount} onChangeText={setAmount} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="ETA (hours)" keyboardType="number-pad" value={eta} onChangeText={setEta} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="Note to owner" value={note} onChangeText={setNote} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <View style={{ height: 12 }} />
      <Button title={busy ? 'Submitting…' : 'Submit Bid'} onPress={submit} disabled={busy} />
    </View>
  );
}
EOF

cat > screens/Transporter/MyBidsScreen.js <<'EOF'
import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, FlatList, RefreshControl } from 'react-native';
import { authFetch } from '../../utils/api';

const currency = (c) => `$${(c/100).toFixed(2)}`;

export default function MyBidsScreen() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try { setRows(await authFetch('/bids/mine')); } finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  return (
    <View style={{ flex:1, padding:12 }}>
      <FlatList
        data={rows}
        keyExtractor={(x) => String(x.id)}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        renderItem={({ item }) => (
          <View style={{ borderWidth:1, borderRadius:8, padding:12, marginBottom:10 }}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>Bid: {currency(item.amount_cents)} • Status: {item.status}</Text>
            <Text>Trip status: {item.trip_status}</Text>
          </View>
        )}
        ListEmptyComponent={!loading && (<Text>No bids yet.</Text>)}
      />
    </View>
  );
}
EOF

cat > screens/Transporter/AwardedTripsScreen.js <<'EOF'
import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, FlatList, RefreshControl } from 'react-native';
import { authFetch } from '../../utils/api';

const currency = (c) => `$${(c/100).toFixed(2)}`;

export default function AwardedTripsScreen() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try { setRows(await authFetch('/bids/awarded')); } finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  return (
    <View style={{ flex:1, padding:12 }}>
      <FlatList
        data={rows}
        keyExtractor={(x) => String(x.id)}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        renderItem={({ item }) => (
          <View style={{ borderWidth:1, borderRadius:8, padding:12, marginBottom:10 }}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>Total: {currency(item.amount_cents)} • You earn: {currency(item.transporter_earnings_cents || 0)}</Text>
            <Text>Status: {item.status}</Text>
          </View>
        )}
        ListEmptyComponent={!loading && (<Text>No awarded trips yet.</Text>)}
      />
    </View>
  );
}
EOF

cat > screens/Chat/ChatScreen.js <<'EOF'
import React, { useEffect, useState, useRef } from 'react';
import { View, Text, TextInput, Button, FlatList, KeyboardAvoidingView, Platform } from 'react-native';
import { authFetch } from '../../utils/api';

export default function ChatScreen({ route }){
  const { bidId } = route.params;
  const [msgs, setMsgs] = useState([]);
  const [text, setText] = useState('');
  const sinceRef = useRef(null);

  async function load(){
    const url = sinceRef.current ? `/chat/messages?bidId=${bidId}&since=${encodeURIComponent(sinceRef.current)}` : `/chat/messages?bidId=${bidId}`;
    const rows = await authFetch(url);
    if(rows.length){
      setMsgs(m => [...m, ...rows]);
      sinceRef.current = rows[rows.length-1].created_at;
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 3000);
    return () => clearInterval(t);
  }, [bidId]);

  async function send(){
    if(!text.trim()) return;
    const m = await authFetch('/chat/send', { method:'POST', body: JSON.stringify({ bidId, body: text })});
    setMsgs(arr => [...arr, m]);
    setText('');
  }

  const render = ({ item }) => (
    <View style={{ alignSelf: 'stretch', marginVertical: 6 }}>
      <Text style={{ fontWeight:'700' }}>{item.sender_user_id}</Text>
      <Text>{item.body}</Text>
      <Text style={{ color:'#888', fontSize:12 }}>{new Date(item.created_at).toLocaleTimeString()}</Text>
    </View>
  );

  return (
    <KeyboardAvoidingView style={{ flex:1 }} behavior={Platform.OS==='ios'?'padding':undefined}>
      <FlatList data={msgs} keyExtractor={x=>String(x.id)} renderItem={render} contentContainerStyle={{ padding:12 }} />
      <View style={{ flexDirection:'row', padding:8, borderTopWidth:1 }}>
        <TextInput style={{ flex:1, borderWidth:1, borderRadius:8, padding:8, marginRight:8 }} value={text} onChangeText={setText} placeholder="Message..." />
        <Button title="Send" onPress={send} />
      </View>
    </KeyboardAvoidingView>
  );
}
EOF

cat > screens/Transporter/MarketScreen.js <<'EOF'
import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl } from 'react-native';
import { authFetch } from '../../utils/api';

export default function MarketScreen({ navigation }){
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const load = async () => { setLoading(true); try { setRows(await authFetch('/market/open-trips')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, []);
  return (
    <View style={{ flex:1, padding:12 }}>
      <FlatList data={rows} keyExtractor={x=>String(x.id)}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        renderItem={({item}) => (
          <TouchableOpacity style={{ borderWidth:1, borderRadius:8, padding:12, marginBottom:10 }}
            onPress={() => navigation.navigate('TripApply', { id: item.id })}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>{item.bid_count} bids</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}
EOF

say "Done!"

cat <<'EOF'

Next steps:

1) Create DB schema:
   psql $DATABASE_URL -f backend/db/schema.sql

2) Backend:
   cd backend
   npm install
   npm run dev    # http://localhost:4242

3) Web:
   cd web
   cp .env.example .env  # fill values (VITE_API_BASE, Firebase, Stripe pk)
   npm install
   npm run dev    # http://localhost:5173

4) Mobile (Expo):
   # in repo root
   npm install
   # set EXPO_PUBLIC_* envs (API base, Stripe pk, Firebase)
   npx expo start

5) Stripe webhook (local testing):
   stripe listen --forward-to localhost:4242/stripe/webhook

Push to GitHub:
   git init && git add . && git commit -m "Initial commit: DogShip"
   git branch -M main
   git remote add origin https://github.com/<you>/dogship.git
   git push -u origin main

EOF
