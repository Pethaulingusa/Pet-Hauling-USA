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
