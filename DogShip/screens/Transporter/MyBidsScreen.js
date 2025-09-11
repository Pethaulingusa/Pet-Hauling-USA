import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, FlatList, RefreshControl } from 'react-native';
import { authFetch } from '../../utils/api';

const currency = (c) => `$${(c/100).toFixed(2)}`;

export default function MyBidsScreen() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try { setRows(await authFetch('/bids/mine')); } finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  return (
    <View style={{ flex:1, padding:12 }}>
      <FlatList
        data={rows}
        keyExtractor={(x) => String(x.id)}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        renderItem={({ item }) => (
          <View style={{ borderWidth:1, borderRadius:8, padding:12, marginBottom:10 }}>
            <Text style={{ fontWeight:'700' }}>{item.pickup_location} → {item.dropoff_location}</Text>
            <Text>Bid: {currency(item.amount_cents)} • Status: {item.status}</Text>
            <Text>Trip status: {item.trip_status}</Text>
          </View>
        )}
        ListEmptyComponent={!loading && (<Text>No bids yet.</Text>)}
      />
    </View>
  );
}
