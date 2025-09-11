import React from 'react';
import { authFetch } from '../api';
import { useLocation } from 'react-router-dom';

export default function Chat(){
  const q = new URLSearchParams(useLocation().search);
  const bidId = q.get('bidId');
  const [msgs, setMsgs] = React.useState([]);
  const [text, setText] = React.useState('');
  const sinceRef = React.useRef(null);

  async function load(){
    const url = sinceRef.current ? `/chat/messages?bidId=${bidId}&since=${encodeURIComponent(sinceRef.current)}` : `/chat/messages?bidId=${bidId}`;
    const rows = await authFetch(url);
    if(rows.length){
      setMsgs(m => [...m, ...rows]);
      sinceRef.current = rows[rows.length-1].created_at;
    }
  }
  React.useEffect(()=>{ load(); const t=setInterval(load, 3000); return ()=>clearInterval(t); }, [bidId]);

  async function send(e){
    e.preventDefault();
    if(!text.trim()) return;
    const m = await authFetch('/chat/send', { method:'POST', body: JSON.stringify({ bidId, body: text })});
    setMsgs(arr => [...arr, m]);
    setText('');
  }

  return (
    <div>
      <h2>Chat</h2>
      <div style={{ border:'1px solid #eee', padding:12, minHeight:240, marginBottom:8 }}>
        {msgs.map(m => (
          <div key={m.id} style={{ marginBottom:8 }}>
            <div><b>{m.sender_user_id}</b> <small>{new Date(m.created_at).toLocaleString()}</small></div>
            <div>{m.body}</div>
          </div>
        ))}
      </div>
      <form onSubmit={send} style={{ display:'flex', gap:8 }}>
        <input value={text} onChange={e=>setText(e.target.value)} placeholder="Message" style={{ flex:1 }} />
        <button>Send</button>
      </form>
    </div>
  );
}
