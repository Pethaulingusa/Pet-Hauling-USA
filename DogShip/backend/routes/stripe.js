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
