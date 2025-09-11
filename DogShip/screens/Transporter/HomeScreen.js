import React from 'react';
import { View, Button } from 'react-native';

export default function TransporterHome({ navigation }){
  return (
    <View style={{ padding:16 }}>
      <Button title="Market" onPress={() => navigation.navigate('Market')} />
      <Button title="My Bids" onPress={() => navigation.navigate('MyBids')} />
      <Button title="Awarded Trips" onPress={() => navigation.navigate('AwardedTrips')} />
    </View>
  );
}
