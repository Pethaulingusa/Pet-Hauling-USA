import React, { useState } from 'react';
import { View, Text, TextInput, Button } from 'react-native';
import { getAuth, signInWithEmailAndPassword, createUserWithEmailAndPassword, updateProfile } from 'firebase/auth';

export default function LoginScreen(){
  const [email, setEmail] = useState('');
  const [pass, setPass] = useState('');
  const [role, setRole] = useState('owner');

  async function login(){ await signInWithEmailAndPassword(getAuth(), email, pass); }
  async function signup(){
    const cred = await createUserWithEmailAndPassword(getAuth(), email, pass);
    await updateProfile(cred.user, { displayName: role });
  }

  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:22 }}>DogShip</Text>
      <TextInput placeholder="Email" value={email} onChangeText={setEmail} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <TextInput placeholder="Password" secureTextEntry value={pass} onChangeText={setPass} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Text>Role: (type owner or transporter)</Text>
      <TextInput placeholder="owner | transporter" value={role} onChangeText={setRole} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Button title="Login" onPress={login} />
      <View style={{ height:8 }} />
      <Button title="Sign up" onPress={signup} />
    </View>
  );
}
