import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, TouchableOpacity, RefreshControl } from 'react-native';
import { authFetch } from '../../utils/api';

export default function MarketScreen({ navigation }){
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const load = async () => { setLoading(true); try { setRows(await authFetch('/market/open-trips')); } finally { setLoading(false); } };
  useEffect(() => { load(); }, []);
  return (
    <View style={{ flex:1, padding:12 }}>
      <FlatList data={rows} keyExtractor={x=>String(x.id)}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        renderItem={({item}) => (
          <TouchableOpacity style={{ borderWidth:1, borderRadius:8, padding:12, marginBottom:10 }}
            onPress={() => navigation.navigate('TripApply', { id: item.id })}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>{item.bid_count} bids</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}
