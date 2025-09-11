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
