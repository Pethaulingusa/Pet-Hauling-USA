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
