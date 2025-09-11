import React from 'react';
import { View, Text, Button } from 'react-native';

export default function TripApplyScreen({ route, navigation }){
  const { id } = route.params;
  return (
    <View style={{ padding:16 }}>
      <Text>Trip #{id}</Text>
      <Button title="Place a Bid" onPress={() => navigation.navigate('PlaceBid', { tripId: id })} />
    </View>
  );
}
