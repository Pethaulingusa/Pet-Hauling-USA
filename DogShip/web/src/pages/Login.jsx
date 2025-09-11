import React, { useState } from 'react';
import { AuthApi } from '../auth';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  return (
    <div>
      <h2>Login / Signup</h2>
      <input placeholder="email" value={email} onChange={e=>setEmail(e.target.value)} />
      <input placeholder="password" type="password" value={password} onChange={e=>setPassword(e.target.value)} />
      <div style={{ display:'flex', gap:8 }}>
        <button onClick={() => AuthApi.login(email, password)}>Login</button>
        <button onClick={() => AuthApi.signup(email, password)}>Signup</button>
      </div>
    </div>
  );
}
