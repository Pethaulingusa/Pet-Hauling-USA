import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Api } from '../api';

const currency = c => `$${(c/100).toFixed(2)}`;

export default function TripBids() {
  const { tripId } = useParams();
  const nav = useNavigate();
  const [rows, setRows] = useState([]);

  useEffect(() => { (async () => {
    setRows(await Api.getBidsForTrip(tripId));
  })(); }, [tripId]);

  const accept = async (bidId) => {
    const resp = await Api.acceptBid(bidId);
    nav('/confirm', { state: { clientSecret: resp.clientSecret, tripId } });
  };

  return (
    <div>
      <h2>Bids</h2>
      {rows.map(b => (
        <div key={b.id} style={{ border:'1px solid #ddd', padding:12, marginBottom:8 }}>
          <div><b>{currency(b.amount_cents)}</b> • ETA {b.eta_hours || '?'}h</div>
          <div>⭐ {Number(b.avg_rating||0).toFixed(1)} ({b.review_count}) • Response {Number(b.response_time_minutes||0).toFixed(1)} min</div>
          <div>{b.note || '—'}</div>
          <button onClick={() => accept(b.id)}>Accept & Pay</button>
          <button onClick={() => nav(`/chat?bidId=${b.id}`)} style={{ marginLeft: 8 }}>Message transporter</button>
        </div>
      ))}
    </div>
  );
}
