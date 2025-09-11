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
