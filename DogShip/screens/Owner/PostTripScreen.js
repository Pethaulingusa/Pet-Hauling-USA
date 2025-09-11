import React, { useState } from 'react';
import { View, Text, TextInput, Button, Alert } from 'react-native';
import { authFetch } from '../../utils/api';

export default function PostTripScreen({ navigation }){
  const [pickup, setPickup] = useState('');
  const [dropoff, setDropoff] = useState('');
  const [dog, setDog] = useState('{"breed":"Labrador"}');

  async function create(){
    try{
      const payload = { pickupLocation: pickup, dropoffLocation: dropoff, dogInfo: JSON.parse(dog || '{}') };
      await authFetch('/trips', { method:'POST', body: JSON.stringify(payload) });
      Alert.alert('Trip posted');
      navigation.goBack();
    }catch(e){ Alert.alert('Error', e.message); }
  }

  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Post Trip</Text>
      <TextInput placeholder="Pickup" value={pickup} onChangeText={setPickup} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <TextInput placeholder="Dropoff" value={dropoff} onChangeText={setDropoff} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Text>Dog JSON</Text>
      <TextInput placeholder='{"breed":"Labrador"}' value={dog} onChangeText={setDog} style={{ borderWidth:1, padding:8, marginVertical:8 }} />
      <Button title="Create Trip" onPress={create} />
    </View>
  );
}
