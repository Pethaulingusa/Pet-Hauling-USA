import React, { useEffect, useState } from 'react';
import { View, Text, Button, FlatList, TouchableOpacity } from 'react-native';
import { auth } from '../../firebase';
import { authFetch } from '../../utils/api';

export default function OwnerHome({ navigation }){
  const [rows, setRows] = useState([]);
  async function load(){
    const uid = auth.currentUser?.uid;
    if (!uid) return;
    const data = await authFetch(`/trips/user/${uid}`);
    setRows(data.filter(t => t.owner_id));
  }
  useEffect(() => { load(); }, []);

  return (
    <View style={{ flex:1, padding:12 }}>
      <Button title="Post Trip" onPress={() => navigation.navigate('PostTrip')} />
      <FlatList data={rows} keyExtractor={x=>String(x.id)}
        renderItem={({ item }) => (
          <TouchableOpacity onPress={() => navigation.navigate('TripDetail', { id: item.id })} style={{ borderWidth:1, padding:12, borderRadius:8, marginVertical:6 }}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>Status: {item.status}</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}
