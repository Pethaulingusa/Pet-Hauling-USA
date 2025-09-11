import React, { useState } from 'react';
import { View, Text, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';
import { useStripe } from '@stripe/stripe-react-native';

const currency = (cents) => `$${(cents/100).toFixed(2)}`;

export default function BidDetailScreen({ route, navigation }) {
  const { bid, feePercent = 15 } = route.params;
  const [busy, setBusy] = useState(false);
  const { initPaymentSheet, presentPaymentSheet } = useStripe();

  const platformFee = Math.round(bid.amount_cents * (feePercent/100));
  const driverGets = bid.amount_cents - platformFee;

  const accept = async () => {
    try {
      setBusy(true);
      const resp = await authFetch(`/bids/${bid.id}/accept`, { method: 'POST' });
      const { clientSecret } = resp;
      await initPaymentSheet({ paymentIntentClientSecret: clientSecret });
      const { error } = await presentPaymentSheet();
      if (error) throw new Error(error.message);
      Alert.alert('Payment confirmed');
      navigation.popToTop();
    } catch (e) {
      Alert.alert('Error', e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight: '700', fontSize: 18 }}>Bid: {currency(bid.amount_cents)}</Text>
      <Text>ETA: {bid.eta_hours || '?'} hours</Text>
      <Text>Note: {bid.note || '—'}</Text>
      <View style={{ height: 10 }} />
      <Text>Platform fee ({feePercent}%): {currency(platformFee)}</Text>
      <Text>Driver gets: {currency(driverGets)}</Text>
      <View style={{ height: 16 }} />
      <Button title={busy ? 'Accepting…' : 'Accept this bid'} onPress={accept} disabled={busy} />
      <View style={{ height: 8 }} />
      <Button title="Message transporter" onPress={() => navigation.navigate('Chat', { bidId: bid.id })} />
    </View>
  );
}
