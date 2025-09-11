import React from 'react';
import { Routes, Route, Link } from 'react-router-dom';
import Login from './pages/Login';
import OwnerDashboard from './pages/OwnerDashboard';
import TransporterDashboard from './pages/TransporterDashboard';
import TripBids from './pages/TripBids';
import StripeConfirm from './pages/StripeConfirm';
import Chat from './pages/Chat';

export default function App() {
  return (
    <div style={{ maxWidth: 900, margin: '0 auto', padding: 16 }}>
      <h1>DogShip Web</h1>
      <nav style={{ display: 'flex', gap: 12 }}>
        <Link to="/">Login</Link>
        <Link to="/owner">Owner</Link>
        <Link to="/transporter">Transporter</Link>
      </nav>
      <Routes>
        <Route path="/" element={<Login />} />
        <Route path="/owner" element={<OwnerDashboard />} />
        <Route path="/transporter" element={<TransporterDashboard />} />
        <Route path="/trip/:tripId/bids" element={<TripBids />} />
        <Route path="/confirm" element={<StripeConfirm />} />
        <Route path="/chat" element={<Chat />} />
      </Routes>
    </div>
  );
}
