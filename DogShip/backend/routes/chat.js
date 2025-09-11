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
