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
