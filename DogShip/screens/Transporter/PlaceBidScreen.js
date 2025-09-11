import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function PlaceBidScreen({ route, navigation }) {
  const { tripId } = route.params;
  const [amount, setAmount] = useState('');
  const [eta, setEta] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!amount) return Alert.alert('Enter an amount');
    setBusy(true);
    try {
      const amountCents = Math.round(parseFloat(amount) * 100);
      await authFetch(`/bids/${tripId}`, { method: 'POST', body: JSON.stringify({ amountCents, etaHours: Number(eta) || null, note }) });
      Alert.alert('Bid placed');
      navigation.goBack();
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally { setBusy(false); }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight: '700', fontSize: 18 }}>Place a Bid</Text>
      <TextInput placeholder="Amount (USD)" keyboardType="decimal-pad" value={amount} onChangeText={setAmount} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="ETA (hours)" keyboardType="number-pad" value={eta} onChangeText={setEta} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="Note to owner" value={note} onChangeText={setNote} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <View style={{ height: 12 }} />
      <Button title={busy ? 'Submitting…' : 'Submit Bid'} onPress={submit} disabled={busy} />
    </View>
  );
}
