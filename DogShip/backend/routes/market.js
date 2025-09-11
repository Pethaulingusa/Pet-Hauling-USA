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
