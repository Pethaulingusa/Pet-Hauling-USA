import React, { useEffect, useState } from 'react';
import { auth } from '../auth';
import { Api } from '../api';
import { Link } from 'react-router-dom';

export default function OwnerDashboard() {
  const [rows, setRows] = useState([]);
  useEffect(() => { (async () => {
    const uid = auth.currentUser?.uid;
    if (!uid) return;
    setRows(await Api.listMyTrips(uid));
  })(); }, []);

  return (
    <div>
      <h2>My Trips</h2>
      {rows.map(t => (
        <div key={t.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{t.pickup_location}</b> → <b>{t.dropoff_location}</b></div>
          <div>Status: {t.status}</div>
          <Link to={`/trip/${t.id}/bids`}>View Bids</Link>
        </div>
      ))}
    </div>
  );
}
