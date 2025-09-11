require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const verifyFirebaseToken = require('./middleware/auth');

const app = express();
const PORT = process.env.PORT || 4242;

app.use(cors({ origin: [process.env.WEB_ORIGIN || 'http://localhost:5173'], credentials: false }));
app.use(bodyParser.json());

// Routers
const stripeRouter = require('./routes/stripe');
const checkrRouter = require('./routes/checkr');
const tripsRouter = require('./routes/trips');
const bidsRouter = require('./routes/bids');
const usersRouter = require('./routes/users');
const marketRouter = require('./routes/market');
const chatRouter = require('./routes/chat');
const notificationsRouter = require('./routes/notifications');

app.get('/', (req, res) => res.send('DogShip Backend Up'));

app.use('/trips', verifyFirebaseToken, tripsRouter);
app.use('/bids', verifyFirebaseToken, bidsRouter);
app.use('/users', verifyFirebaseToken, usersRouter);
app.use('/market', verifyFirebaseToken, marketRouter);
app.use('/chat', verifyFirebaseToken, chatRouter);
app.use('/notifications', verifyFirebaseToken, notificationsRouter);

// Stripe webhook (raw body inside)
app.use('/stripe', stripeRouter);

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
