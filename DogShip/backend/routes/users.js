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
