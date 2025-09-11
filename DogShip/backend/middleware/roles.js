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
