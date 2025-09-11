import React from 'react';
import { View, Text, Button } from 'react-native';

export default function TripDetailScreen({ route, navigation }){
  const { id } = route.params;
  return (
    <View style={{ padding:16 }}>
      <Text style={{ fontWeight:'700', fontSize:18 }}>Trip #{id}</Text>
      <View style={{ height:8 }} />
      <Button title="View Bids" onPress={() => navigation.navigate('Bids', { tripId: id, feePercent: 15 })} />
    </View>
  );
}
