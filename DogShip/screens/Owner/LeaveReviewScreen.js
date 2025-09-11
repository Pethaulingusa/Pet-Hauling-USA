import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function LeaveReviewScreen({ route, navigation }){
  const { tripId } = route.params;
  const [rating, setRating] = useState('5');
  const [comment, setComment] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    try {
      setBusy(true);
      const payload = { rating: Number(rating), comment };
      await authFetch(`/reviews/trip/${tripId}/owner-to-transporter`, { method: 'POST', body: JSON.stringify(payload) });
      Alert.alert('Thanks!', 'Your review has been submitted.');
      navigation.goBack();
    } catch (e) { Alert.alert('Error', e.message); } finally { setBusy(false); }
  };

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Rate your driver</Text>
      <TextInput placeholder="Rating (1-5)" keyboardType="number-pad" value={rating} onChangeText={setRating} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <TextInput placeholder="Comment" value={comment} onChangeText={setComment} style={{ borderWidth:1, marginTop:10, padding:8, borderRadius:8 }} />
      <View style={{ height: 12 }} />
      <Button title={busy ? 'Submitting…' : 'Submit Review'} onPress={submit} disabled={busy} />
    </View>
  );
}
