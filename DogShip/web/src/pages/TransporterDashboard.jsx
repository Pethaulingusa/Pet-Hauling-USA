import React, { useEffect, useState } from 'react';
import { Api, authFetch } from '../api';
import { Link } from 'react-router-dom';

export default function TransporterDashboard() {
  const [open, setOpen] = useState([]);
  const [myBids, setMyBids] = useState([]);

  useEffect(() => { (async () => {
    setOpen(await authFetch('/market/open-trips'));
    setMyBids(await Api.myBids());
  })(); }, []);

  return (
    <div>
      <h2>Open Trips</h2>
      {open.map(t => (
        <div key={t.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{t.pickup_location}</b> → <b>{t.dropoff_location}</b></div>
          <div>{t.bid_count} bids</div>
          <Link to={`/trip/${t.id}/bids`}>View / Place Bid</Link>
        </div>
      ))}

      <h2>My Bids</h2>
      {myBids.map(b => (
        <div key={b.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div>{b.pickup_location} → {b.dropoff_location}</div>
          <div>Amount: ${(b.amount_cents/100).toFixed(2)} • Status: {b.status} • Trip: {b.trip_status}</div>
        </div>
      ))}
    </div>
  );
}
